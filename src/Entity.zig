const std = @import("std");

const linalg = @import("./linalg.zig");
const Game = @import("./Game.zig");
const RenderContext = @import("./RenderContext.zig");

const Self = @This();

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

alive: bool = false,

tick: *const fn(self: *Self, ctx: *const TickContext) void = noopTick,
draw: *const fn(self: *Self, game: *Game, ctx: *RenderContext) void = noopDraw,
input: *const fn(self: *Self, game: *Game, input: Game.Input) void = undefined,
camera: *const fn(self: *Self, game: *Game, ctx: *RenderContext) void = undefined,

aux: union(enum) {
    player: struct {
        last_input: Game.Input = .{},
        roll: f32 = 0.0,
    },
} = undefined,

state: enum {
    air,
    ground,
    fly,
} = .air,

origin: linalg.Vec3 = linalg.Vec3.zero(),
half_extents: linalg.Vec3 = linalg.Vec3.zero(),

velocity: linalg.Vec3 = linalg.Vec3.zero(),

on_ground: bool = false,
