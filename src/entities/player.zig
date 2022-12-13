const std = @import("std");

const linalg = @import("../linalg.zig");
const c = @import("../c.zig");
const Game = @import("../Game.zig");
const RenderContext = @import("../RenderContext.zig");
const Entity = @import("../Entity.zig");
const Model = @import("../Model.zig");
const Sequence = @import("../Sequence.zig");

const STEPHEIGHT = 0.2;

const TIMER_ATTACK_TIME = 0;

const CAMERA_OFFSET = linalg.Vec3.new(0.0, 0.0, 0.8);

const BALANCE_SHOTGUN_REFIRE = 1.0;

const SEQFLAG_INTERRUPTIBLE = 1 << 0;
const SEQFLAG_EXTRA_ROUND = 1 << 1;

const shotgun_idle = Sequence.init(&.{
    .{ .set_flags = SEQFLAG_INTERRUPTIBLE },
    .{ .frame_range = .{ .start = 40.0, .end = 40.0, .framerate = -1.0 } },
    .restart,
});

const shotgun_fire = Sequence.init(&.{
    .{ .set_flags = SEQFLAG_EXTRA_ROUND },
    .{ .frame_range = .{ .start = 40.0, .end = 75.0, .framerate = 60.0 } },
    .{ .frame_range = .{ .start = 100.0, .end = 169.0, .framerate = 60.0 } },
    .{ .replace_with = &shotgun_idle },
});

fn shotgunAttack(self: *Entity, ctx: *const Entity.TickContext, forward: linalg.Vec3, right: linalg.Vec3) void {
    const up = forward.cross(right);

    const origin = self.origin.add(CAMERA_OFFSET);

    var pellets: usize = 10;

    const spread: [2]f32 = .{ 0.2, 0.05 };

    while (pellets > 0) : (pellets -= 1) {
        const bullet_dir =
            forward
            .add(right.mulScalar(spread[0] * (ctx.game.rand.float(f32) * 2.0 - 1.0)))
            .add(up.mulScalar(spread[1] * (ctx.game.rand.float(f32) * 2.0 - 1.0)))
            .mulScalar(100.0);

        const impact = ctx.game.traceLine(origin, linalg.Vec3.zero(), bullet_dir, self.createIgnore()) orelse continue;
        if (impact.entity) |ent| {
            ent.alive = false;
        }
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
    self.velocity = self.velocity.add(movement.mulScalar(ctx.delta * 120.0));

    self.velocity.data[2] = 0.0;

    self.walkMove(ctx, STEPHEIGHT);

    if (!self.on_ground) {
        self.state = .air;
    }

    if (self.aux.player.last_input.key(.jump)) {
        self.velocity.data[2] = 10.0;

        self.state = .air;
    }
}

fn tickWeapon(self: *Entity, ctx: *const Entity.TickContext, forward: linalg.Vec3, right: linalg.Vec3) void {
    self.sequences[0].tick(self, ctx);

    if (self.sequences[0].flag(SEQFLAG_INTERRUPTIBLE)) {
        if (self.aux.player.last_input.key(.attack) and self.aux.player.shells_loaded > 0) {
            self.sequences[0] = shotgun_fire;

            shotgunAttack(self, ctx, forward, right);
        }
    }
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

    const roll_target = std.math.clamp(self.velocity.dot(right) * 0.1, -1.0, 1.0) / -30.0;

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

    const camera =
        linalg.Mat4.translation(0.076, -0.1, -0.14)
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(1.0, 0.0, 0.0), std.math.pi * -0.5));

    child_ctx.matrix_camera_to_world = camera.inverse();
    child_ctx.matrix_world_to_camera = camera;

    c.glDepthRange(0.0, 0.1);
    self.models[1].?.drawFiltered(&child_ctx, linalg.Mat4.identity(), &frames, "grid");
    c.glDepthRange(0.0, 1.0);

    game.dbg_gizmo.draw(ctx, linalg.Mat4.translationVector(self.debug_position), &frames);
}

fn drawTransparentFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var frames = calculateShotgunFrames(self);

    var child_ctx = ctx.*;

    child_ctx.matrix_projection = linalg.Mat4.perspective(1.1, ctx.aspect, 0.01, 10.0);

    const camera =
        linalg.Mat4.translation(0.076, -0.1, -0.14)
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(1.0, 0.0, 0.0), std.math.pi * -0.5));

    child_ctx.matrix_camera_to_world = camera.inverse();
    child_ctx.matrix_world_to_camera = camera;

    c.glDepthRange(0.0, 0.1);
    self.models[1].?.drawFiltered(&child_ctx, linalg.Mat4.identity(), &frames, "shaders");
    c.glDepthRange(0.0, 1.0);
}

pub fn spawn(self: *Entity, game: *Game) void {
    self.origin = linalg.Vec3.new(-2.0, 0.0, 1.2);
    self.half_extents = linalg.Vec3.new(0.6, 0.6, 1.2);

    self.models[1] = game.asset_manager.load(Model, "weapons/shotgun/shotgun.model") catch null;

    self.tick = tickFn;
    self.input = inputFn;
    self.camera = cameraFn;
    self.draw = drawFn;
    self.drawTransparent = drawTransparentFn;

    self.aux = .{
        .player = .{},
    };

    self.sequences[0] = shotgun_idle;
}
