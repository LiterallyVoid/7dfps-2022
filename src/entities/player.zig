const std = @import("std");

const linalg = @import("../linalg.zig");
const c = @import("../c.zig");
const Game = @import("../Game.zig");
const RenderContext = @import("../RenderContext.zig");
const Entity = @import("../Entity.zig");
const Model = @import("../Model.zig");

const STEPHEIGHT = 0.2;

const TIMER_ATTACK_TIME = 0;

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

fn tickWeapon(self: *Entity, ctx: *const Entity.TickContext) void {
    self.timers[TIMER_ATTACK_TIME] += ctx.delta * 60.0;
    if (self.timers[TIMER_ATTACK_TIME] > 75.0 and self.timers[TIMER_ATTACK_TIME] < 100.0) {
        self.timers[TIMER_ATTACK_TIME] = 100.0;
    }

    if (self.timers[TIMER_ATTACK_TIME] > 168.0) {
        self.timers[TIMER_ATTACK_TIME] = 168.0;

        if (self.aux.player.last_input.key(.attack)) {
            self.timers[TIMER_ATTACK_TIME] = 40.0;
        }
    }
}

fn tickFn(self: *Entity, ctx: *const Entity.TickContext) void {
    var input = self.aux.player.last_input;

    var camera =
        linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), input.angle[1])
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), std.math.pi * 0.5))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), std.math.pi * 0.5));

    var forward = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(0.0, 0.0, -1.0));
    var right = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(1.0, 0.0, 0.0));

    var movement = forward.mulScalar(input.movement[1]).add(right.mulScalar(input.movement[0]));

    const roll_target = std.math.clamp(self.velocity.dot(right) * 0.1, -1.0, 1.0) / -30.0;

    const roll_interp = 1.0 - std.math.pow(f32, 0.5, ctx.delta * 30.0);

    self.aux.player.roll = self.aux.player.roll * (1.0 - roll_interp) + roll_target * roll_interp;

    switch (self.state) {
        .ground => moveGround(self, ctx, movement),
        .air => moveAir(self, ctx, movement),
        else => unreachable,
    }

    tickWeapon(self, ctx);
}

fn inputFn(self: *Entity, game: *Game, input: Game.Input) void {
    _ = game;

    self.aux.player.last_input = input;
}

fn cameraFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var camera =
        linalg.Mat4.translation(self.origin.data[0], self.origin.data[1], self.origin.data[2] + 0.8)
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), self.aux.player.last_input.angle[1]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), self.aux.player.last_input.angle[0]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), std.math.pi * 0.5));

    camera = camera.multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), self.aux.player.roll));

    ctx.matrix_projection = linalg.Mat4.perspective(1.5, ctx.aspect, 0.1, 1000.0);

    ctx.matrix_camera_to_world = camera;
    ctx.matrix_world_to_camera = camera.inverse();
}

fn drawFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var frames = .{
        .{
            .frame = self.timers[TIMER_ATTACK_TIME],
            .weight = 1.0,
        },
    };

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
}

fn drawTransparentFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    var frames = .{
        .{
            .frame = self.timers[TIMER_ATTACK_TIME],
            .weight = 1.0,
        },
    };

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
}
