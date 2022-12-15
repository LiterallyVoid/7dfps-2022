const std = @import("std");

const linalg = @import("../linalg.zig");
const c = @import("../c.zig");
const Game = @import("../Game.zig");
const RenderContext = @import("../RenderContext.zig");
const Entity = @import("../Entity.zig");
const Model = @import("../Model.zig");
const Sequence = @import("../Sequence.zig");
const Inter = @import("../Inter.zig");

const STEPHEIGHT = 0.2;

const CAMERA_OFFSET = linalg.Vec3.new(0.0, 0.0, 0.8);

const ENTFLAG_CANCEL_RELOAD: u32 = 1 << 0;

const SEQFLAG_INTERRUPTIBLE = 1 << 0;
const SEQFLAG_EXTRA_ROUND = 1 << 1;
const SEQFLAG_CANCELLABLE = 1 << 2;

const SHOTGUN_FRAMERATE = 60.0;
const SHOTGUN_RELOAD_FRAMERATE = 90.0;

const shotgun_idle = Sequence.init(&.{
    .{ .set_flags = SEQFLAG_INTERRUPTIBLE },
    .{ .frame_range = .{ .start = 40.0, .end = 40.0, .framerate = 0.0 } },
    .restart,
});

const shotgun_fire = Sequence.init(&.{
    .{ .set_flags = SEQFLAG_EXTRA_ROUND },
    .{ .frame_range = .{ .start = 40.0, .end = 75.0, .framerate = SHOTGUN_FRAMERATE } },
    .{ .frame_range = .{ .start = 100.0, .end = 160.0, .framerate = SHOTGUN_FRAMERATE } },
    .{ .set_flags = SEQFLAG_INTERRUPTIBLE },
    .{ .frame_range = .{ .start = 160.0, .end = 169.0, .framerate = SHOTGUN_FRAMERATE } },
    .{ .replace_with = &shotgun_idle },
});

const shotgun_reload_begin = Sequence.init(&.{
    .{ .frame_range = .{ .start = 181.0, .end = 200.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .set_flags = SEQFLAG_EXTRA_ROUND | SEQFLAG_CANCELLABLE },
    .{ .frame_range = .{ .start = 213.0, .end = 241.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .call_function = .{ .callback = sLoadShell } },
});

const shotgun_reload_begin_tac = Sequence.init(&.{
    .{ .frame_range = .{ .start = 181.0, .end = 200.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .replace_with = &shotgun_reload_shell },
});

const shotgun_reload_shell = Sequence.init(&.{
    .{ .set_flags = SEQFLAG_CANCELLABLE },
    .{ .set_flags = SEQFLAG_EXTRA_ROUND },
    .{ .frame_range = .{ .start = 242.0, .end = 272.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .call_function = .{ .callback = sLoadShell } },
});

const shotgun_reload_end = Sequence.init(&.{
    .{ .frame_range = .{ .start = 273.0, .end = 303.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .set_flags = SEQFLAG_INTERRUPTIBLE },
    .{ .frame_range = .{ .start = 303.0, .end = 315.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .replace_with = &shotgun_idle },
});

fn sLoadShell(self: *Entity, ctx: *const Entity.TickContext) void {
    _ = ctx;
    self.aux.player.shells_loaded += 1;

    if (self.aux.player.shells_loaded < 5 and (self.flags & ENTFLAG_CANCEL_RELOAD) == 0) {
        self.sequences[0] = shotgun_reload_shell;
    } else {
        self.flags &= ~ENTFLAG_CANCEL_RELOAD;
        self.sequences[0] = shotgun_reload_end;
    }
}

fn shotgunAttack(self: *Entity, ctx: *const Entity.TickContext, forward: linalg.Vec3, right: linalg.Vec3) void {
    self.flags &= ~ENTFLAG_CANCEL_RELOAD;

    const up = right.cross(forward);

    const origin = self.origin.add(CAMERA_OFFSET);

    var pellets: usize = 10;

    const spread: [2]f32 = .{ 0.1, 0.05 };

    while (pellets > 0) : (pellets -= 1) {
        const bullet_dir =
            forward
            .add(right.mulScalar(spread[0] * (ctx.game.rand.float(f32) * 2.0 - 1.0)))
            .add(up.mulScalar(spread[1] * (ctx.game.rand.float(f32) * 2.0 - 1.0)))
            .mulScalar(100.0);

        const impact = ctx.game.traceLine(origin, linalg.Vec3.zero(), bullet_dir, self.createIgnore()) orelse continue;
        var flesh = false;

        if (impact.entity) |ent| {
            if (ent.max_health > 0) flesh = true;
            ent.damage(ctx, 6.0, self);
        }

        if (flesh) {
            ctx.game.particles.effectOne(
                "impact-flesh",
                origin.add(bullet_dir.mulScalar(impact.time)),
                impact.plane.xyz(),
            ) catch unreachable;
        } else {
            ctx.game.particles.effectOne(
                "shotgun-impact",
                origin.add(bullet_dir.mulScalar(impact.time)),
                impact.plane.xyz(),
            ) catch unreachable;
        }

        ctx.game.particles.effectOne(
            "shotgun-tracer",
            origin
                .add(up.mulScalar(-0.1))
                .add(right.mulScalar(0.07))
                .add(forward.mulScalar(0.5 + 0.14)),
            bullet_dir.mulScalar(impact.time),
        ) catch unreachable;
    }
}

fn shotgunReload(self: *Entity) void {
    if (self.aux.player.shells_loaded == 0) {
        self.sequences[0] = shotgun_reload_begin;
    } else if (self.aux.player.shells_loaded < 5) {
        self.sequences[0] = shotgun_reload_begin_tac;
    }
}

fn moveAir(self: *Entity, ctx: *const Entity.TickContext, movement: linalg.Vec3) void {
    self.move(ctx);

    self.velocity = self.velocity.mulScalar(std.math.pow(f32, 0.5, ctx.delta * 0.5));
    self.velocity = self.velocity.add(movement.mulScalar(ctx.delta * 2.0));

    self.velocity.data[2] -= ctx.delta * 30.0;

    if (self.on_ground) {
        self.state = .ground;
    }
}

fn moveGround(self: *Entity, ctx: *const Entity.TickContext, movement: linalg.Vec3) void {
    self.velocity = self.velocity.mulScalar(std.math.pow(f32, 0.5, ctx.delta * 20.0));
    self.velocity = self.velocity.add(movement.mulScalar(ctx.delta * 100.0));

    self.velocity.data[2] = 0.0;

    self.walkMove(ctx, STEPHEIGHT);

    if (!self.on_ground) {
        self.state = .air;
    }

    if (self.aux.player.last_input.keyPressed(.jump)) {
        self.velocity.data[2] = 10.0;

        self.state = .air;
    }
}

fn tickWeapon(self: *Entity, ctx: *const Entity.TickContext, forward: linalg.Vec3, right: linalg.Vec3) void {
    if (self.sequences[0].flag(SEQFLAG_INTERRUPTIBLE)) {
        if (self.aux.player.last_input.keyHeld(.attack)) {
            if (self.aux.player.shells_loaded > 0) {
                shotgunAttack(self, ctx, forward, right);

                self.sequences[0] = shotgun_fire;

                self.aux.player.shells_loaded -= 1;
            } else {
                shotgunReload(self);
            }
        }

        if (self.aux.player.last_input.keyHeld(.reload)) {
            shotgunReload(self);
        }
    } else {
        if (self.aux.player.last_input.keyPressed(.attack) and self.sequences[0].flag(SEQFLAG_CANCELLABLE)) {
            self.flags |= ENTFLAG_CANCEL_RELOAD;
        }
    }

    self.sequences[0].tick(self, ctx);
}

fn tickFn(self: *Entity, ctx: *const Entity.TickContext) void {
    const input = self.aux.player.last_input;

    const camera =
        linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), input.angle[1])
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), input.angle[0]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), std.math.pi * 0.5));

    const forward = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(0.0, 0.0, -1.0));
    const right = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(1.0, 0.0, 0.0));

    const horizontal_forward = linalg.Vec3.new(0.0, 0.0, 1.0).cross(right);

    const movement = horizontal_forward.mulScalar(input.movement[1]).add(right.mulScalar(input.movement[0]));

    const roll_target = std.math.clamp(self.velocity.dot(right) * 0.1, -1.0, 1.0) / -15.0;

    const roll_interp = 1.0 - std.math.pow(f32, 0.5, ctx.delta * 30.0);

    self.aux.player.roll = self.aux.player.roll * (1.0 - roll_interp) + roll_target * roll_interp;

    switch (self.state) {
        .ground => moveGround(self, ctx, movement),
        .air => moveAir(self, ctx, movement),
        else => unreachable,
    }

    tickWeapon(self, ctx, forward, right);

    const impact = ctx.game.traceLine(self.origin.add(CAMERA_OFFSET), linalg.Vec3.zero(), forward.mulScalar(32.0), self.createIgnore()) orelse return;

    self.debug_position = self.origin.add(CAMERA_OFFSET).add(forward.mulScalar(32.0 * impact.time));
}

fn inputFn(self: *Entity, game: *Game, input: Game.Input) void {
    _ = game;

    self.aux.player.last_input = input;
}

fn cameraFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var camera =
        linalg.Mat4.translationVector(self.origin.add(CAMERA_OFFSET))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), self.aux.player.last_input.angle[1]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), self.aux.player.last_input.angle[0]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), std.math.pi * 0.5));

    camera = camera.multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), self.aux.player.roll));

    ctx.matrix_projection = linalg.Mat4.perspective(1.5, ctx.aspect, 0.1, 1000.0);

    ctx.matrix_camera_to_world = camera;
    ctx.matrix_world_to_camera = camera.inverse();
}

fn calculateShotgunFrames(self: *Entity) [2]Model.ModelFrame {
    var shells_displayed = self.aux.player.shells_loaded;

    var base_frame: f32 = self.sequences[0].frame;

    if (self.sequences[0].flag(SEQFLAG_EXTRA_ROUND)) {
        shells_displayed += 1;
    }

    return .{
        .{
            .frame = base_frame,
            .weight = 1.0,
        },
        .{
            .frame = @intToFloat(f32, 25 - shells_displayed),
            .weight = 1.0,
        },
    };
}

fn drawFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    var frames = calculateShotgunFrames(self);

    var child_ctx = ctx.*;

    child_ctx.matrix_projection = linalg.Mat4.perspective(1.1, ctx.aspect, 0.01, 10.0);

    const model_matrix =
        ctx.matrix_camera_to_world
        .multiply(linalg.Mat4.translation(0.076, -0.1, -0.14))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(1.0, 0.0, 0.0), std.math.pi * -0.5));

    c.glDepthRange(0.0, 0.1);
    self.models[1].?.drawFiltered(&child_ctx, model_matrix, &frames, "grid");
    c.glDepthRange(0.0, 1.0);

    game.dbg_gizmo.draw(ctx, linalg.Mat4.translationVector(self.debug_position), &frames);
}

fn drawTransparentFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var frames = calculateShotgunFrames(self);

    var child_ctx = ctx.*;

    child_ctx.matrix_projection = linalg.Mat4.perspective(1.1, ctx.aspect, 0.01, 10.0);

    const model_matrix =
        ctx.matrix_camera_to_world
        .multiply(linalg.Mat4.translation(0.076, -0.1, -0.14))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(1.0, 0.0, 0.0), std.math.pi * -0.5));

    c.glDepthRange(0.0, 0.1);
    self.models[1].?.drawFiltered(&child_ctx, model_matrix, &frames, "shaders");
    c.glDepthRange(0.0, 1.0);
}

fn drawUIFn(self: *Entity, game: *Game, into: *Inter.Viewport) void {
    _ = game;

    var buf: [1024]u8 = undefined;
    const health = std.fmt.bufPrint(&buf, "{}", .{ @floatToInt(i32, self.health) }) catch "???";

    into.next().anchored(.{0.1, 0.9}, .{0.0, 1.0}).fontSize(100.0).text(health).pad(.{20.0, 10.0}).done();

    const ammo = std.fmt.bufPrint(&buf, "{}/5", .{ self.aux.player.shells_loaded }) catch "???";
    into.next().anchored(.{0.9, 0.9}, .{1.0, 1.0}).fontSize(100.0).text(ammo).pad(.{20.0, 10.0}).done();

    into.next().anchored(.{0.0, 0.0}, .{0.0, 0.0}).fontSize(10.0).color(.{255, 48, 48, 255}).text("LIGHTING NEEDS TO BE REBUILT (5 unbuilt objects)").pad(.{ 10.0, 10.0 }).done();
}

pub fn spawn(self: *Entity, game: *Game) void {
    self.team = .player;

    self.health = 100.0;
    self.max_health = 100.0;

    self.origin = linalg.Vec3.new(-2.0, 0.0, 1.2);
    self.half_extents = linalg.Vec3.new(0.6, 0.6, 1.2);

    self.models[1] = game.asset_manager.load(Model, "weapons/shotgun/shotgun.model") catch null;

    self.tick = tickFn;
    self.input = inputFn;
    self.camera = cameraFn;
    self.draw = drawFn;
    self.drawTransparent = drawTransparentFn;
    self.drawUI = drawUIFn;

    self.aux = .{
        .player = .{
            .shells_loaded = 5,
        },
    };

    self.sequences[0] = shotgun_idle;
}
