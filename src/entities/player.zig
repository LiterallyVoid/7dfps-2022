const std = @import("std");

const util = @import("../util.zig");
const linalg = @import("../linalg.zig");
const c = @import("../c.zig");
const Game = @import("../Game.zig");
const RenderContext = @import("../RenderContext.zig");
const Entity = @import("../Entity.zig");
const Model = @import("../Model.zig");
const Sequence = @import("../Sequence.zig");
const Inter = @import("../Inter.zig");

const STEPHEIGHT = 0.5;

const CAMERA_OFFSET = linalg.Vec3.new(0.0, 0.0, 0.8);

const TIMER_SWAY = 0;

const ENTFLAG_CANCEL_RELOAD: u32 = 1 << 0;
const ENTFLAG_JUMP_DEBOUNCE: u32 = 1 << 1;

const SEQFLAG_INTERRUPTIBLE = 1 << 0;
const SEQFLAG_EXTRA_ROUND = 1 << 1;
const SEQFLAG_CANCELLABLE = 1 << 2;
const SEQFLAG_INHIBIT_MELEE = 1 << 3;

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
    .{ .frame_range = .{ .start = 100.0, .end = 112.0, .framerate = SHOTGUN_FRAMERATE } },
    .{ .call_function = .{ .callback = sSoundMech } },
    .{ .frame_range = .{ .start = 112.0, .end = 124.0, .framerate = SHOTGUN_FRAMERATE } },
    .{ .call_function = .{ .callback = sSoundMech } },
    .{ .frame_range = .{ .start = 124.0, .end = 160.0, .framerate = SHOTGUN_FRAMERATE } },
    .{ .set_flags = SEQFLAG_INTERRUPTIBLE },
    .{ .frame_range = .{ .start = 160.0, .end = 169.0, .framerate = SHOTGUN_FRAMERATE } },
    .{ .replace_with = &shotgun_idle },
});

const shotgun_reload_begin = Sequence.init(&.{
    .{ .frame_range = .{ .start = 181.0, .end = 200.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .set_flags = SEQFLAG_EXTRA_ROUND | SEQFLAG_CANCELLABLE },
    .{ .call_function = .{ .callback = sSoundMech } },
    .{ .frame_range = .{ .start = 213.0, .end = 238.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
    .{ .call_function = .{ .callback = sSoundMech } },
    .{ .frame_range = .{ .start = 238.0, .end = 241.0, .framerate = SHOTGUN_RELOAD_FRAMERATE } },
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

const quick_melee = Sequence.init(&.{
    .{ .set_flags = SEQFLAG_INHIBIT_MELEE },
    .{ .frame_range = .{ .start = 320.0, .end = 324.0, .framerate = 60.0 } },
    .{ .call_function = .{ .callback = quickMelee } },
    .{ .frame_range = .{ .start = 324.0, .end = 350.0, .framerate = 40.0 } },
    .{ .clear_flags = SEQFLAG_INHIBIT_MELEE },
    .{ .set_flags = SEQFLAG_INTERRUPTIBLE },
    .{ .frame_range = .{ .start = 350.0, .end = 360.0, .framerate = 40.0 } },
    .{ .replace_with = &shotgun_idle },
});

fn quickMelee(self: *Entity, ctx: *const Entity.TickContext) void {
    const dir =
        self.forward
        .mulScalar(4.0 + self.velocity.length() * 0.2);

    const impact = ctx.game.traceLine(self.origin.add(CAMERA_OFFSET), linalg.Vec3.broadcast(0.2), dir, self.createIgnore()) orelse return;

    var impact_point = self.origin.add(CAMERA_OFFSET).add(dir.mulScalar(impact.time));

    ctx.game.app.playSound(ctx.game.sound_melee_hit, .{ .entity = self });

    var flesh = false;

    if (self.velocity.data[2] < 0.0) self.velocity.data[2] = 0.0;
    self.velocity = self.velocity.add(self.forward.mulScalar(-10.0));

    if (impact.entity) |ent| {
        if (ent.max_health > 0) flesh = true;
        ent.damage(ctx, 20.0, self);
    }

    if (flesh) {
        ctx.game.particles.effectOne(
            "knife-flesh",
            impact_point,
            impact_point.sub(impact.entity.?.origin).normalized(),
        ) catch unreachable;
    } else {
        ctx.game.particles.effectOne(
            "knife-impact",
            impact_point,
            impact.plane.xyz(),
        ) catch unreachable;
    }
}

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

fn sSoundMech(self: *Entity, ctx: *const Entity.TickContext) void {
    ctx.game.app.playSound(ctx.game.sound_shotgun_mech, .{ .entity = self });
}

fn shotgunAttack(self: *Entity, ctx: *const Entity.TickContext, forward: linalg.Vec3, right: linalg.Vec3) void {
    self.velocity = self.velocity.add(self.forward.mulScalar(-18.0));

    self.flags &= ~ENTFLAG_CANCEL_RELOAD;

    const up = right.cross(forward);

    const origin = self.origin.add(CAMERA_OFFSET);

    var pellets: usize = 10;

    const spread: [2]f32 = .{ 0.16, 0.02 };

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
            ent.damage(ctx, 10.0, self);
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

    self.velocity = self.velocity.mulScalar(std.math.pow(f32, 0.5, ctx.delta * 0.1));
    self.velocity = self.velocity.add(movement.mulScalar(ctx.delta * 10.0));

    self.velocity.data[2] -= ctx.delta * 30.0;

    if (self.on_ground) {
        self.state = .ground;
    }
}

fn moveGround(self: *Entity, ctx: *const Entity.TickContext, movement: linalg.Vec3) void {
    self.velocity = self.velocity.mulScalar(std.math.pow(f32, 0.5, ctx.delta * 20.0));
    self.velocity = self.velocity.add(movement.mulScalar(ctx.delta * 130.0));

    self.velocity.data[2] = 0.0;

    self.walkMove(ctx, STEPHEIGHT);

    if (!self.on_ground) {
        self.state = .air;
    }

    if (self.aux.player.last_input.keyHeld(.jump) and !self.getFlag(ENTFLAG_JUMP_DEBOUNCE)) {
        self.setFlag(ENTFLAG_JUMP_DEBOUNCE);
        self.velocity.data[2] = 10.0;

        self.state = .air;
    }
}

fn tickWeapon(self: *Entity, ctx: *const Entity.TickContext, forward: linalg.Vec3, right: linalg.Vec3) void {
    if (!self.sequences[0].flag(SEQFLAG_INHIBIT_MELEE) and self.aux.player.last_input.keyPressed(.quick_melee)) {
        self.sequences[0] = quick_melee;
    }

    if (self.sequences[0].flag(SEQFLAG_INTERRUPTIBLE)) {
        if (self.aux.player.last_input.keyHeld(.attack)) {
            if (self.aux.player.shells_loaded > 0) {
                shotgunAttack(self, ctx, forward, right);

                ctx.game.app.playSound(ctx.game.sound_shoot, .{ .entity = self });
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

fn interpolateAngleTo(to: *f32, from: f32, factor: f32) void {
    const angle_diff = util.angleWrap(from - to.*);

    to.* += angle_diff * (1.0 - std.math.pow(f32, 0.5, factor));
    to.* = util.angleWrap(to.*);
}

fn tickFn(self: *Entity, ctx: *const Entity.TickContext) void {
    if (self.health < self.aux.player.last_health - 1.0) {
        self.aux.player.damage_flourish = 1.0;
    }

    self.aux.player.last_health = self.health;
    self.aux.player.damage_flourish -= ctx.delta * 3.0;
    self.aux.player.damage_flourish = std.math.clamp(self.aux.player.damage_flourish, 0.0, 1.0);

    interpolateAngleTo(&self.view_angle[0], self.aux.player.last_input.angle[0], 1.0 - std.math.pow(f32, 0.5, ctx.delta * 60.0));
    interpolateAngleTo(&self.view_angle[1], self.aux.player.last_input.angle[1], 1.0 - std.math.pow(f32, 0.5, ctx.delta * 60.0));

    const input = self.aux.player.last_input;

    const camera =
        linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), input.angle[1])
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), input.angle[0]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), std.math.pi * 0.5));

    const forward = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(0.0, 0.0, -1.0));
    const right = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(1.0, 0.0, 0.0));

    self.forward = forward;

    const horizontal_forward = linalg.Vec3.new(0.0, 0.0, 1.0).cross(right);

    var movement = horizontal_forward.mulScalar(input.movement[1]).add(right.mulScalar(input.movement[0]));
    if (movement.length() > 1.0) {
        movement = movement.normalized();
    }

    const roll_target = std.math.clamp(self.velocity.dot(right) * 0.1, -1.0, 1.0) / -15.0;

    const roll_interp = 1.0 - std.math.pow(f32, 0.5, ctx.delta * 30.0);

    self.aux.player.roll = self.aux.player.roll * (1.0 - roll_interp) + roll_target * roll_interp;

    switch (self.state) {
        .ground => moveGround(self, ctx, movement),
        .air => moveAir(self, ctx, movement),
        else => unreachable,
    }

    if (!self.aux.player.last_input.keyHeld(.jump)) {
        self.clearFlag(ENTFLAG_JUMP_DEBOUNCE);
    }

    tickWeapon(self, ctx, forward, right);

    const target_velocity_smooth = self.velocity.mulScalar(if (self.state == .ground) 1.0 else 0.3);

    self.velocity_smooth = self.velocity_smooth.add(target_velocity_smooth.sub(self.velocity_smooth).mulScalar(1.0 - std.math.pow(f32, 0.5, ctx.delta * 20.0)));

    self.timers[TIMER_SWAY] += ctx.delta * (2.0 + self.velocity_smooth.length() * 0.5);
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

    ctx.matrix_projection = linalg.Mat4.perspective(1.5, ctx.aspect, 0.1, 100.0);

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

fn sigmoid(value_: f32) f32 {
    const value = util.angleWrap(value_);

    const in_scale = 1.5;
    const out_scale = 1.2;
    return ((1 / (1 + std.math.exp(-value / in_scale))) - 0.5) * out_scale;
}

fn calculateShotgunMatrix(self: *Entity, ctx: *RenderContext) linalg.Mat4 {
    const sway_x = sigmoid(self.view_angle[0] - self.aux.player.last_input.angle[0]);
    const sway_y = sigmoid(self.view_angle[1] - self.aux.player.last_input.angle[1]);
    const bob_phase = std.math.sin(self.timers[TIMER_SWAY]);
    const bob_amt = self.velocity_smooth.length() * 0.004;

    return
        linalg.Mat4.translation(self.velocity_smooth.data[0] * 0.001, self.velocity_smooth.data[1] * 0.001, 0.0)
        .multiply(ctx.matrix_camera_to_world)
        .multiply(linalg.Mat4.translation(std.math.sin(bob_phase) * bob_amt, (-std.math.cos(bob_phase) + 0.4) * bob_amt, 0.0))
        .multiply(linalg.Mat4.translation(0.076, -0.1, -0.14))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(1.0, 0.0, 0.0), std.math.pi * -0.5))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(1.0, 0.0, 0.0), sway_x))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), sway_y));
}

fn drawFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var frames = calculateShotgunFrames(self);

    var child_ctx = ctx.*;

    child_ctx.matrix_projection = linalg.Mat4.perspective(1.1, ctx.aspect, 0.01, 10.0);

    const model_matrix = calculateShotgunMatrix(self, ctx);

    c.glDepthRange(0.0, 0.1);
    self.models[1].?.drawFiltered(&child_ctx, model_matrix, &frames, "grid");
    c.glDepthRange(0.0, 1.0);
}

fn drawTransparentFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var frames = calculateShotgunFrames(self);

    var child_ctx = ctx.*;

    child_ctx.matrix_projection = linalg.Mat4.perspective(1.1, ctx.aspect, 0.01, 10.0);

    const model_matrix = calculateShotgunMatrix(self, ctx);

    c.glDepthRange(0.0, 0.1);
    self.models[1].?.drawFiltered(&child_ctx, model_matrix, &frames, "shaders");
    c.glDepthRange(0.0, 1.0);
}

fn drawUIFn(self: *Entity, game: *Game, into: *Inter.Viewport) void {
    var buf: [1024]u8 = undefined;
    const health = std.fmt.bufPrint(&buf, "{}", .{ @floatToInt(i32, self.health) }) catch "???";

    const health_color = linalg.Vec4.new(1.0, 1.0, 1.0, 1.0)
        .mix(linalg.Vec4.new(1.0, 0.1, 0.1, 1.0), self.aux.player.damage_flourish)
        .mulScalar(255.0);

    into.next().anchored(.{0.1, 0.9}, .{0.0, 1.0}).color(health_color.toArray(u8)).fontSize(100.0).text(health).pad(.{20.0, 10.0}).done();

    const ammo = std.fmt.bufPrint(&buf, "{}/5", .{ self.aux.player.shells_loaded }) catch "???";
    into.next().anchored(.{0.9, 0.9}, .{1.0, 1.0}).fontSize(100.0).text(ammo).pad(.{20.0, 10.0}).done();

    var rebuilt_buf: [512]u8 = undefined;

    var enemies_alive: usize = 0;

    for (game.entities) |entity| {
        if (entity.alive and entity.team == .enemy) enemies_alive += 1;
    }

    if (enemies_alive > 0) {
        const rebuilt_txt = std.fmt.bufPrint(&rebuilt_buf, "Lighting needs to be rebuilt ({} unbuilt objects)", .{ enemies_alive }) catch "";

        into.next().anchored(.{0.0, 0.0}, .{0.0, 0.0}).fontSize(5.0).color(.{255, 48, 48, 255}).text(rebuilt_txt).pad(.{ 10.0, 10.0 }).done();
    } else {
        into.next().anchored(.{0.5, 0.6}, .{0.5, 1.0}).fontSize(40.0).color(.{255, 255, 255, 255}).text("YOU WIN!").pad(.{ 10.0, 10.0 }).done();

        const time = std.fmt.bufPrint(&rebuilt_buf, "in {d:.2} seconds", .{ game.victory_time }) catch "";
        into.next().anchored(.{0.5, 0.6}, .{0.5, 0.0}).fontSize(40.0).color(.{255, 255, 255, 255}).text(time).pad(.{ 10.0, 10.0 }).done();
    }

    into.next().anchored(.{0.5, 0.5}, .{0.5, 0.5}).image(game.crosshair_tex.*, .{30.0, 30.0}).done();
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
