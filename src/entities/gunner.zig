const std = @import("std");

const linalg = @import("../linalg.zig");
const util = @import("../util.zig");
const Game = @import("../Game.zig");
const RenderContext = @import("../RenderContext.zig");
const Entity = @import("../Entity.zig");
const Model = @import("../Model.zig");

const STEPHEIGHT = 0.2;

const TIMER_ATTACK = 0;
const TIMER_WALK_FRAME = 1;
const TIMER_WALK_WEIGHT = 2;
const TIMER_ATTACK_ENTER = 3;
const TIMER_ATTACK_REFIRE = 4;
const TIMER_ATTACK_LIMIT = 5;
const TIMER_GUN_ROTATION = 6;
const TIMER_GUN_ROTATION_VELOCITY = 7;

const keyframe_attack_hurt = 37.0;
const keyframe_attack_done = 115.0;

fn attack(self: *Entity, ctx: *const Entity.TickContext) void {
    const forward = self.matrix().multiplyVector(linalg.Vec4.new(0.0, -1.0, 0.0, 0.0)).xyz();
    const attack_half_extents = linalg.Vec3.new(1.1, 1.1, 0.2);
    const attack_origin = self.origin.add(forward.mulScalar(2.5));

    var ignore = self.createIgnore();
    ignore.map = true;

    const impact = ctx.game.nudge(attack_origin, attack_half_extents, ignore) orelse return;

    if (impact.entity) |ent| {
        ent.velocity = ent.velocity.add(ent.origin.sub(self.origin).mulScalar(12.0));
        ent.state = .air;
    }
}

fn interpolateAngleTo(to: *f32, from: f32, factor: f32) void {
    const angle_diff = @mod(from - to.* + std.math.pi, std.math.pi * 2) - std.math.pi;

    to.* += angle_diff * (1.0 - std.math.pow(f32, 0.5, factor));
    to.* = util.angleWrap(to.*);
}

fn shoot(self: *Entity, ctx: *const Entity.TickContext) void {
    const origin = self.origin.add(linalg.Vec3.new(0.0, 0.0, 0.2));

    const matrix = linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), self.angle.data[2] + self.view_angle[0] + std.math.pi * 0.5)
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), self.view_angle[1] + std.math.pi * 0.5))
        .toMat3();

    const forward = matrix.multiplyVectorOpp(linalg.Vec3.new(0.0, 0.0, -1.0));
    const right = matrix.multiplyVectorOpp(linalg.Vec3.new(0.0, 1.0, 0.0));
    const up = forward.cross(right);

    const dir = forward
        .add(right.mulScalar((ctx.game.rand.float(f32) * 2.0 - 1.0) * 0.03))
        .add(up.mulScalar((ctx.game.rand.float(f32) * 2.0 - 1.0) * 0.03))
        .mulScalar(50.0);

    const impact = ctx.game.traceLine(origin, linalg.Vec3.zero(), dir, self.createIgnore()) orelse return;

    if (impact.entity) |entity| {
        entity.damage(ctx, 9.0, self);
    }

    ctx.game.particles.effectOne(
        "chaingun-tracer",
        origin,
        dir.mulScalar(impact.time),
    ) catch unreachable;

    ctx.game.app.playSound(ctx.game.sound_chaingun_shoot, .{ .entity = self });
}

fn tickFn(self: *Entity, ctx: *const Entity.TickContext) void {
    self.processEnemyLOS(ctx);

    if (!self.awake) return;

    const delta_to_player = self.target_position.sub(self.origin);

    self.timers[TIMER_GUN_ROTATION] += self.timers[TIMER_GUN_ROTATION_VELOCITY] * ctx.delta;
    self.timers[TIMER_GUN_ROTATION] = @mod(self.timers[TIMER_GUN_ROTATION], 1.0);

    if (self.state == .attack) {
        self.timers[TIMER_WALK_WEIGHT] *= std.math.pow(f32, 0.5, ctx.delta * 10.0);

        self.timers[TIMER_ATTACK_LIMIT] -= ctx.delta;

        if (self.timers[TIMER_ATTACK_LIMIT] < 0.0) {
            self.view_angle[0] *= std.math.pow(f32, 0.5, ctx.delta * 10.0);
            self.view_angle[1] *= std.math.pow(f32, 0.5, ctx.delta * 10.0);

            if (self.timers[TIMER_ATTACK_LIMIT] < -0.2) {
                self.state = .ground;
            }

            return;
        } else if (!self.has_los) {
            self.timers[TIMER_ATTACK_LIMIT] = 0.0;
        }

        self.velocity = linalg.Vec3.zero();

        if (self.has_los) {
            const target_angle = std.math.atan2(f32, delta_to_player.data[1], delta_to_player.data[0])
                + std.math.pi * 0.5
                - self.angle.data[2];

            const target_vertical_angle = std.math.atan2(f32, delta_to_player.data[2], delta_to_player.xy().length());

            interpolateAngleTo(&self.view_angle[0], target_angle, ctx.delta * 4.0);
            interpolateAngleTo(&self.view_angle[1], target_vertical_angle, ctx.delta * 4.0);
        }

        self.view_angle[0] = std.math.clamp(self.view_angle[0], -std.math.pi * 0.5, std.math.pi * 0.5);
        self.view_angle[1] = std.math.clamp(self.view_angle[1], -std.math.pi * 0.5, std.math.pi * 0.5);

        self.timers[TIMER_ATTACK_REFIRE] -= ctx.delta;
        if (self.timers[TIMER_ATTACK_REFIRE] < 0.0) {
            self.timers[TIMER_ATTACK_REFIRE] = 0.1;
            shoot(self, ctx);
        }

        self.timers[TIMER_GUN_ROTATION_VELOCITY] -= 20.0;
        self.timers[TIMER_GUN_ROTATION_VELOCITY] *= std.math.pow(f32, 0.5, ctx.delta * 4.0);
        self.timers[TIMER_GUN_ROTATION_VELOCITY] += 20.0;
    } else if (self.state == .ground) {
        self.timers[TIMER_GUN_ROTATION_VELOCITY] *= std.math.pow(f32, 0.5, ctx.delta * 10.0);

        const target_angle = std.math.atan2(f32, delta_to_player.data[1], delta_to_player.data[0]) + std.math.pi * 0.5;
        interpolateAngleTo(&self.angle.data[2], target_angle, ctx.delta * 10.0);
        self.view_angle = .{ 0.0, 0.0 };

        const walk_speed: f32 = if (self.victory) 0.0 else 1.0;

        const walk_rate: f32 = 50.0;

        self.timers[TIMER_WALK_WEIGHT] += (walk_speed - self.timers[TIMER_WALK_WEIGHT]) * (1.0 - std.math.pow(f32, 0.5, ctx.delta * 10.0));

        self.timers[TIMER_WALK_FRAME] += ctx.delta * walk_rate;
        self.timers[TIMER_WALK_FRAME] = @mod(self.timers[TIMER_WALK_FRAME], 40.0);

        if (self.has_los) {
            self.timers[TIMER_ATTACK] -= ctx.delta;
        }

        if (self.timers[TIMER_ATTACK] < 0.0 and self.has_los) {
            self.timers[TIMER_ATTACK] = ctx.game.rand.float(f32) * 0.5 + 0.5;
            self.timers[TIMER_ATTACK_LIMIT] = 3.0;
            self.timers[TIMER_ATTACK_REFIRE] = 0.6;
            self.state = .attack;
        }

        const forward_speed = 2.5 * 2.0 * (6.0 / 4.0) * walk_speed;

        self.velocity = self.matrix().multiplyVector(linalg.Vec4.new(0.0, -forward_speed, 0.0, 0.0)).xyz();

        self.walkMove(ctx, 1.0);

        if (!self.on_ground) {
            self.state = .air;
        }
    } else if (self.state == .air) {
        self.timers[TIMER_WALK_WEIGHT] += (0.25 - self.timers[TIMER_WALK_WEIGHT]) * (1.0 - std.math.pow(f32, 0.5, ctx.delta * 10.0));
        self.timers[TIMER_WALK_FRAME] += ctx.delta * 30.0;
        self.timers[TIMER_WALK_FRAME] = @mod(self.timers[TIMER_WALK_FRAME], 60.0);
        self.velocity.data[2] -= ctx.delta * 30.0;

        self.move(ctx);
        if (self.on_ground) {
            self.state = .ground;
        }
    }
}

fn drawFn(self: *Entity, game: *Game, ctx: *RenderContext) void {
    _ = game;

    const gun_rotation_frame = .{
        .frame = 100.0 + self.timers[TIMER_GUN_ROTATION] * 5.0,
        .weight = 1.0,
    };

    var frames_walk = [_]Model.ModelFrame{
        .{
            .frame = self.timers[TIMER_WALK_FRAME] + 10.0,
            .weight = self.timers[TIMER_WALK_WEIGHT],
        },
        gun_rotation_frame,
    };

    var frames_attack = [_]Model.ModelFrame{
        .{
            .frame = self.timers[TIMER_WALK_FRAME] + 10.0,
            .weight = self.timers[TIMER_WALK_WEIGHT],
        },
        .{
            .frame = 75.0 + self.view_angle[1] * (10.0 / std.math.pi),
            .weight = 1.0,
        },
        .{
            .frame = 86.0 + self.view_angle[0] * (10.0 / std.math.pi),
            .weight = 1.0,
        },
        gun_rotation_frame,
    };

    var frames = switch (self.state) {
        .ground => &frames_walk,
        .attack => &frames_attack,
        .air => &frames_walk,
        else => unreachable,
    };

    self.models[0].?.draw(ctx, self.matrix(), frames);
}

pub fn spawn(self: *Entity, game: *Game) void {
    self.timers[TIMER_ATTACK] = 0.3;
    self.timers[TIMER_ATTACK_LIMIT] = 3.0;

    self.team = .enemy;

    self.health = 50.0;
    self.max_health = 50.0;

    self.origin = linalg.Vec3.new(2.0, 0.0, 1.4);
    self.half_extents = linalg.Vec3.new(0.6, 0.6, 1.4);
    self.model_offset = linalg.Vec3.new(0.0, 0.0, -1.4);

    self.tick = tickFn;
    self.draw = drawFn;

    self.models[0] = game.asset_manager.load(Model, "enemies/gunner/gunner.model") catch null;

    self.state = .ground;
}
