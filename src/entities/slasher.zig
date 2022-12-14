const std = @import("std");

const linalg = @import("../linalg.zig");
const Game = @import("../Game.zig");
const RenderContext = @import("../RenderContext.zig");
const Entity = @import("../Entity.zig");
const Model = @import("../Model.zig");

const STEPHEIGHT = 0.2;

const TIMER_ATTACK = 0;
const TIMER_WALK_FRAME = 1;
const TIMER_WALK_WEIGHT = 2;
const TIMER_ATTACK_FRAME = 3;

const FLAG_HAS_ATTACKED = 1 << 0;

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

fn tickFn(self: *Entity, ctx: *const Entity.TickContext) void {
    if (self.state == .attack) {
        self.timers[TIMER_WALK_WEIGHT] *= std.math.pow(f32, 0.5, ctx.delta * 10.0);
        self.timers[TIMER_ATTACK_FRAME] += ctx.delta * 60.0;

        if (!self.getFlag(FLAG_HAS_ATTACKED) and self.timers[TIMER_ATTACK_FRAME] > keyframe_attack_hurt) {
            self.setFlag(FLAG_HAS_ATTACKED);
            attack(self, ctx);
        }

        if (self.timers[TIMER_ATTACK_FRAME] > keyframe_attack_done) {
            self.clearFlag(FLAG_HAS_ATTACKED);
            self.state = .ground;
            self.timers[TIMER_ATTACK_FRAME] = 0.0;
        }

        self.velocity = linalg.Vec3.zero();
    } else if (self.state == .ground) {
        const delta_to_player = ctx.game.player.origin.sub(self.origin);

        const target_angle = std.math.atan2(f32, delta_to_player.data[1], delta_to_player.data[0]) + std.math.pi * 0.5;
        const angle_diff = @mod(target_angle - self.angle.data[2] + std.math.pi, std.math.pi * 2) - std.math.pi;
        self.angle.data[2] += angle_diff * (1.0 - std.math.pow(f32, 0.5, ctx.delta * 4.0));

        const walk_speed: f32 = std.math.min(1.4, delta_to_player.length() / 3.0);

        self.timers[TIMER_WALK_WEIGHT] += (walk_speed - self.timers[TIMER_WALK_WEIGHT]) * (1.0 - std.math.pow(f32, 0.5, ctx.delta * 10.0));
        self.timers[TIMER_WALK_FRAME] += ctx.delta * 60.0;
        self.timers[TIMER_WALK_FRAME] = @mod(self.timers[TIMER_WALK_FRAME], 60.0);

        self.timers[TIMER_ATTACK] -= ctx.delta;
        if (self.timers[TIMER_ATTACK] < 0.0 and delta_to_player.length() < 3.5) {
            self.timers[TIMER_ATTACK] = ctx.game.rand.float(f32) * 2.0 + 1.0;
            self.state = .attack;
        }

        const forward_speed = 12.0 * 0.2 * walk_speed;

        self.velocity = self.matrix().multiplyVector(linalg.Vec4.new(0.0, -forward_speed, 0.0, 0.0)).xyz();

        self.walkMove(ctx, 0.2);

        if (!self.on_ground) {
            self.state = .air;
        }
    } else if (self.state == .air) {
        self.timers[TIMER_ATTACK_FRAME] = 0.0;
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

    var frames = .{
        .{
            .frame = self.timers[TIMER_ATTACK_FRAME],
            .weight = 1.0,
        },
        .{
            .frame = self.timers[TIMER_WALK_FRAME] + 140.0,
            .weight = self.timers[TIMER_WALK_WEIGHT],
        },
    };

    self.models[0].?.draw(ctx, self.matrix(), &frames);
}

pub fn spawn(self: *Entity, game: *Game) void {
    self.health = 50.0;
    self.max_health = 50.0;

    self.origin = linalg.Vec3.new(2.0, 0.0, 1.2);
    self.half_extents = linalg.Vec3.new(0.6, 0.6, 1.2);
    self.model_offset = linalg.Vec3.new(0.0, 0.0, -1.2);

    self.tick = tickFn;
    self.draw = drawFn;

    self.models[0] = game.asset_manager.load(Model, "enemies/slasher/slasher.model") catch null;

    self.state = .ground;
}
