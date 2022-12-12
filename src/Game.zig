const std = @import("std");

const asset = @import("./asset.zig");
const c = @import("./c.zig");
const linalg = @import("./linalg.zig");
const util = @import("./util.zig");

const Map = @import("./Map.zig");
const Entity = @import("./Entity.zig");
const RenderContext = @import("./RenderContext.zig");

const ent_player = @import("./entities/player.zig");

const Self = @This();

const MAXENTITIES = 1024;

pub const Input = struct {
    const Key = enum(u32) {
        jump,

    };

    angle: [2]f32 = .{ 0.0, 0.0 }, // pitch, yaw

    movement: [2]f32 = .{ 0.0, 0.0 },
    keys: [4]bool = [1]bool{ false } ** 4,

    pub fn key(self: Input, k: Key) bool {
        return self.keys[@enumToInt(k)];
    }
};

map: *Map,
entities: [MAXENTITIES]Entity,
player: *Entity,

pub fn init(self: *Self, am: *asset.Manager, map: []const u8) !void {
    self.* = .{
        .map = try am.load(Map, map),
        .entities = [1]Entity{ .{} } ** MAXENTITIES,
        .player = undefined,
    };

    self.player = self.spawn().?;
    ent_player.spawn(self.player, self);
}

pub fn deinit(self: *Self, am: *asset.Manager) void {
    am.drop(self.map);
}

pub fn spawn(self: *Self) ?*Entity {
    for (self.entities) |*entity| {
        if (entity.alive) continue;

        entity.* = .{ .alive = true, };
        return entity;
    }

    return null;
}

pub fn input(self: *Self, input_data: Input) void {
    self.player.input(self.player, self, input_data);
}

pub fn update(self: *Self, delta: f32) void {
    var ctx = Entity.TickContext {
        .game = self,
        .delta = delta,
    };

    for (self.entities) |*entity| {
        if (!entity.alive) continue;

        entity.tick(entity, &ctx);
    }
}

pub fn draw(self: *Self, ctx: *RenderContext) void {
    self.player.camera(self.player, self, ctx);

    var child_ctx = ctx.*;

    self.map.draw(&child_ctx);

    c.glEnable(c.GL_CULL_FACE);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);
    self.map.drawTransparent(&child_ctx);
    c.glDisable(c.GL_BLEND);
}
