const std = @import("std");

const linalg = @import("./linalg.zig");
const Game = @import("./Game.zig");
const RenderContext = @import("./RenderContext.zig");
const PhysicsMesh = @import("./PhysicsMesh.zig");
const Model = @import("./Model.zig");
const Sequence = @import("./Sequence.zig");
const Inter = @import("./Inter.zig");

const Self = @This();

pub const MARGIN = 0.01;

pub const TickContext = struct {
    game: *Game,
    delta: f32,
};

fn noopTick(self: *Self, ctx: *const TickContext) void {
    _ = self;
    _ = ctx;
}

fn noopDraw(self: *Self, game: *Game, ctx: *RenderContext) void {
    _ = self;
    _ = game;
    _ = ctx;
}

pub fn createIgnore(self: *Self) PhysicsMesh.Ignore {
    return .{
        .entity = self,
    };
}

pub fn traceVertical(self: *Self, ctx: *const TickContext, offset: f32) ?f32 {
    if (ctx.game.traceLine(self.origin, self.half_extents.sub(linalg.Vec3.broadcast(MARGIN)), linalg.Vec3.new(0.0, 0.0, offset), self.createIgnore())) |impact| {
        if (impact.plane.data[2] > 0.7) self.on_ground = true;
        return impact.time * offset + MARGIN * 2.0 * if (offset < 0.0) @as(f32, -1.0) else 1.0;
    }

    return null;
}

pub fn move(self: *Self, ctx: *const TickContext) void {
    self.on_ground = false;

    if (ctx.game.nudge(self.origin, self.half_extents.add(linalg.Vec3.broadcast(MARGIN)), self.createIgnore())) |impact| {
        self.origin = self.origin.add(impact.offset);

        const into = self.velocity.dot(impact.plane.xyz());

        if (into < 0.0) {
            if (impact.plane.data[2] > 0.7) self.on_ground = true;
            self.velocity = self.velocity.sub(impact.plane.xyz().mulScalar(into));
        }
    }

    {
        var i: usize = 0;
        var remaining: f32 = 1.0;

        while (i < 4) : (i += 1) {
            var offset = self.velocity.mulScalar(ctx.delta * remaining);

            var impact = ctx.game.traceLine(self.origin, self.half_extents, offset, self.createIgnore()) orelse {
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

pub fn walkMove(self: *Self, ctx: *const TickContext, step_height: f32) void {
    const up_movement = self.traceVertical(ctx, step_height) orelse step_height;

    self.origin.data[2] += up_movement;
    self.move(ctx);

    if (self.traceVertical(ctx, -step_height - up_movement)) |down_movement| {
        self.origin.data[2] += down_movement;
    } else {
        self.origin.data[2] -= up_movement;
        self.on_ground = false;
    }
}

pub fn matrix(self: *Self) linalg.Mat4 {
    return linalg.Mat4.translation(self.origin.data[0] + self.model_offset.data[0], self.origin.data[1] + self.model_offset.data[1], self.origin.data[2] + self.model_offset.data[2])
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), self.angle.data[2]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), self.angle.data[0]))
        .multiply(linalg.Mat4.rotation(linalg.Vec3.new(1.0, 0.0, 0.0), self.angle.data[1]));
}

pub fn setFlag(self: *Self, flags: u32) void {
    self.flags |= flags;
}

pub fn clearFlag(self: *Self, flags: u32) void {
    self.flags &= ~flags;
}

pub fn getFlag(self: *Self, flags: u32) bool {
    return (self.flags & flags) == flags;
}

pub fn processEnemyLOS(self: *Self, ctx: *const TickContext) void {
    if (!ctx.game.player.alive) {
        self.has_los = false;
        self.victory = true;
        return;
    }

    if (self.los_timer > 0.0) {
        if (self.has_los) {
            self.target_position = ctx.game.player.origin;
        }

        self.los_timer -= ctx.delta;
        return;
    }

    self.los_timer = 0.1;

    const delta_to_player = ctx.game.player.origin.sub(self.origin);

    self.has_los = false;
    var los_ignore = self.createIgnore();
    los_ignore.team = self.team;

    if (ctx.game.traceLine(self.origin, linalg.Vec3.zero(), delta_to_player.mulScalar(100.0), los_ignore)) |los_impact| {
        if (los_impact.entity == ctx.game.player) {
            self.has_los = true;
        }
    }

    if (self.has_los) {
        self.target_position = ctx.game.player.origin;
    }

    if (delta_to_player.smallerThan(20.0)) {
        if (self.has_los) {
            self.awake = true;
        }
    }
    if (!delta_to_player.smallerThan(35.0)) {
        self.awake = false;
    }
}

pub const Team = enum {
    neutral,
    player,
    enemy,
};

pub fn damage(self: *Self, ctx: *const TickContext, dmg: f32, source: *Self) void {
    if (self.max_health < 0.0) return;
    self.health -= dmg;

    if (self.health <= 0.0) {
        self.alive = false;

        ctx.game.particles.effectOne(
            "DEATH",
            self.origin,
            linalg.Vec3.zero(),
        ) catch unreachable;
        ctx.game.app.playSound(ctx.game.sound_murder, .{ .entity = self });
    }

    self.velocity = self.velocity.add(source.origin.sub(self.origin).normalized().mulScalar(-dmg));
    if (self.velocity.data[2] > 1.0) {
        self.state = .air;
    }
}

health: f32 = -1.0,
max_health: f32 = -1.0,

alive: bool = false,

tick: *const fn (self: *Self, ctx: *const TickContext) void = noopTick,
draw: *const fn (self: *Self, game: *Game, ctx: *RenderContext) void = noopDraw,
drawTransparent: *const fn (self: *Self, game: *Game, ctx: *RenderContext) void = noopDraw,
input: *const fn (self: *Self, game: *Game, input: Game.Input) void = undefined,
camera: *const fn (self: *Self, game: *Game, ctx: *RenderContext) void = undefined,
drawUI: *const fn (self: *Self, game: *Game, into: *Inter.Viewport) void = undefined,

aux: union(enum) {
    player: struct {
        last_input: Game.Input = .{},
        roll: f32 = 0.0,
        shells_loaded: u32 = 5,
        damage_flourish: f32 = 0.0,
        last_health: f32 = 100.0,
    },
} = undefined,

state: enum {
    air,
    ground,
    fly,
    attack,
} = .air,

origin: linalg.Vec3 = linalg.Vec3.zero(),
half_extents: linalg.Vec3 = linalg.Vec3.zero(),
model_offset: linalg.Vec3 = linalg.Vec3.zero(),

angle: linalg.Vec3 = linalg.Vec3.zero(),

velocity: linalg.Vec3 = linalg.Vec3.zero(),
velocity_smooth: linalg.Vec3 = linalg.Vec3.zero(),

// only for players
forward: linalg.Vec3 = linalg.Vec3.zero(),

on_ground: bool = false,

models: [16]?*Model = [1]?*Model{null} ** 16,

flags: u32 = 0,

timers: [8]f32 = [1]f32{0.0} ** 8,
sequences: [2]Sequence = .{undefined} ** 2,

debug_position: linalg.Vec3 = linalg.Vec3.zero(),

// only for gunner! nobody else gets it
view_angle: [2]f32 = .{ 0.0, 0.0 },
target_position: linalg.Vec3 = linalg.Vec3.zero(),

has_los: bool = false,
los_timer: f32 = 0.0,

victory: bool = false,

team: Team = .neutral,

awake: bool = false,
