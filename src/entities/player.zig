const std = @import("std");

const linalg = @import("../linalg.zig");
const Game = @import("../Game.zig");
const RenderContext = @import("../RenderContext.zig");
const Entity = @import("../Entity.zig");

const MARGIN = 0.0001;
const STEPHEIGHT = 0.2;

fn move(self: *Entity, ctx: *const Entity.TickContext) void {
    self.on_ground = false;

    if (ctx.game.map.phys_mesh.nudge(self.origin, self.half_extents.add(linalg.Vec3.broadcast(MARGIN)))) |impact| {
        self.origin = self.origin.add(impact.offset);

        const into = self.velocity.dot(impact.plane.xyz());

        if (into < 0.0) {
            self.velocity = self.velocity.sub(impact.plane.xyz().mulScalar(into));
        }
    }

    {
        var i: usize = 0;
        var remaining: f32 = 1.0;

        while (i < 4) : (i += 1) {
            var offset = self.velocity.mulScalar(ctx.delta * remaining);

            var impact = ctx.game.map.phys_mesh.traceLine(self.origin, self.half_extents, offset) orelse {
                self.origin = self.origin.add(offset);
                break;
            };

            if (impact.plane.data[2] > 0.7) self.on_ground = true;

            self.origin = self.origin.add(offset.mulScalar(impact.time));

            self.velocity = self.velocity.sub(impact.plane.xyz().mulScalar(self.velocity.dot(impact.plane.xyz())));
            remaining *= 1.0 - impact.time;
        }
    }
}

fn traceVertical(self: *Entity, ctx: *const Entity.TickContext, offset: f32) ?f32 {
    if (ctx.game.map.phys_mesh.traceLine(self.origin, self.half_extents.sub(linalg.Vec3.broadcast(MARGIN)), linalg.Vec3.new(0.0, 0.0, offset))) |impact| {
        return impact.time * offset + MARGIN * 2.0 * if (offset < 0.0) @as(f32, -1.0) else 1.0;
    }

    return null;
}

fn moveAir(self: *Entity, ctx: *const Entity.TickContext, movement: linalg.Vec3) void {
    move(self, ctx);

    self.velocity = self.velocity.mulScalar(std.math.pow(f32, 0.5, ctx.delta * 0.5));
    self.velocity = self.velocity.add(movement.mulScalar(ctx.delta * 2.0));

    self.velocity.data[2] -= ctx.delta * 30.0;

    if (self.on_ground) {
        self.state = .ground;
    }
}

fn moveGround(self: *Entity, ctx: *const Entity.TickContext, movement: linalg.Vec3) void {
    const up_movement = traceVertical(self, ctx, STEPHEIGHT) orelse STEPHEIGHT;

    self.origin.data[2] += up_movement;

    move(self, ctx);

    self.velocity = self.velocity.mulScalar(std.math.pow(f32, 0.5, ctx.delta * 20.0));
    self.velocity = self.velocity.add(movement.mulScalar(ctx.delta * 120.0));

    self.velocity.data[2] = 0.0;

    if (traceVertical(self, ctx, -STEPHEIGHT - up_movement)) |down_movement| {
        self.origin.data[2] += down_movement;
    } else {
        self.origin.data[2] -= up_movement;

        self.state = .air;
    }

    if (self.aux.player.last_input.key(.jump)) {
        self.velocity.data[2] = 10.0;

        self.state = .air;
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

pub fn spawn(self: *Entity, game: *Game) void {
    _ = game;

    self.half_extents = linalg.Vec3.new(0.6, 0.6, 1.2);

    self.tick = tickFn;
    self.input = inputFn;
    self.camera = cameraFn;

    self.aux = .{
        .player = .{},
    };
}
