const std = @import("std");

const asset = @import("./asset.zig");
const c = @import("./c.zig");
const linalg = @import("./linalg.zig");
const util = @import("./util.zig");

const Map = @import("./Map.zig");
const Entity = @import("./Entity.zig");
const RenderContext = @import("./RenderContext.zig");

const PhysicsMesh = @import("./PhysicsMesh.zig");

const ent_player = @import("./entities/player.zig");
const ent_slasher = @import("./entities/slasher.zig");

const Self = @This();

const MAXENTITIES = 1024;

pub const Input = struct {
    const Key = enum(u32) {
        jump,
        attack,
    };

    angle: [2]f32 = .{ 0.0, 0.0 }, // pitch, yaw

    movement: [2]f32 = .{ 0.0, 0.0 },
    keys: [4]bool = [1]bool{false} ** 4,

    pub fn key(self: Input, k: Key) bool {
        return self.keys[@enumToInt(k)];
    }
};

asset_manager: *asset.Manager,
map: *Map,
entities: [MAXENTITIES]Entity,
player: *Entity,

prng: std.rand.DefaultPrng,
rand: std.rand.Random,

pub fn init(self: *Self, am: *asset.Manager, map: []const u8) !void {
    self.* = .{
        .asset_manager = am,
        .map = try am.load(Map, map),
        .entities = [1]Entity{.{}} ** MAXENTITIES,
        .player = undefined,

        .prng = std.rand.DefaultPrng.init(1337),
        .rand = undefined,
    };

    self.rand = self.prng.random();

    self.player = self.spawn().?;
    ent_player.spawn(self.player, self);

    const slasher = self.spawn().?;
    ent_slasher.spawn(slasher, self);
}

pub fn deinit(self: *Self) void {
    for (self.entities) |entity| {
        for (entity.models) |model_opt| {
            const model = model_opt orelse continue;
            self.asset_manager.drop(model);
        }
    }

    self.asset_manager.drop(self.map);
}

pub fn spawn(self: *Self) ?*Entity {
    for (self.entities) |*entity| {
        if (entity.alive) continue;

        entity.* = .{
            .alive = true,
        };
        return entity;
    }

    return null;
}

pub fn input(self: *Self, input_data: Input) void {
    self.player.input(self.player, self, input_data);
}

pub fn update(self: *Self, delta: f32) void {
    var ctx = Entity.TickContext{
        .game = self,
        .delta = std.math.min(delta, 1.0 / 15.0),
    };

    for (self.entities) |*entity| {
        if (!entity.alive) {
            for (entity.models) |model_opt| {
                const model = model_opt orelse continue;
                self.asset_manager.drop(model);
            }

            continue;
        }

        entity.tick(entity, &ctx);
    }
}

pub fn draw(self: *Self, ctx: *RenderContext) void {
    c.glEnable(c.GL_CULL_FACE);

    c.glDepthRange(0.0, 1.0);

    self.player.camera(self.player, self, ctx);

    var child_ctx = ctx.*;

    self.map.draw(&child_ctx);

    for (self.entities) |*entity| {
        if (!entity.alive) continue;
        if (entity == self.player) continue;

        entity.draw(entity, self, ctx);
    }

    self.player.draw(self.player, self, ctx);

    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glDepthMask(c.GL_FALSE);
    self.map.drawTransparent(&child_ctx);

    for (self.entities) |*entity| {
        if (!entity.alive) continue;
        if (entity == self.player) continue;

        entity.drawTransparent(entity, self, ctx);
    }

    self.player.drawTransparent(self.player, self, ctx);

    c.glDisable(c.GL_BLEND);
    c.glDepthMask(c.GL_TRUE);
}

fn boxNudge(point: linalg.Vec3, half_extents: linalg.Vec3, ent_origin: linalg.Vec3, ent_half_extents: linalg.Vec3) ?PhysicsMesh.Impact {
    var closest: f32 = std.math.inf(f32);
    var closest_nudge = linalg.Vec3.zero();
    var closest_plane = linalg.Vec4.zero();

    var i: usize = 0;

    while (i < 3) : (i += 1) {
        var a_min = point.data[i] - half_extents.data[i];
        var a_max = point.data[i] + half_extents.data[i];

        var b_min = ent_origin.data[i] - ent_half_extents.data[i];
        var b_max = ent_origin.data[i] + ent_half_extents.data[i];

        if (a_min > b_max or b_min > a_max) return null;

        var direction = linalg.Vec3.zero();
        var distance: f32 = 0.0;

        if (point.data[i] < ent_origin.data[i]) {
            direction.data[i] = -1.0;
            distance = (half_extents.data[i] + ent_half_extents.data[i]) - (ent_origin.data[i] - point.data[i]);
        } else {
            direction.data[i] = 1.0;
            distance = (half_extents.data[i] + ent_half_extents.data[i]) - (point.data[i] - ent_origin.data[i]);
        }

        if (distance < closest) {
            closest = distance;

            closest_nudge = direction.mulScalar(distance);
            closest_plane = direction.xyzw(ent_origin.data[i] * -direction.data[i] - ent_half_extents.data[i]);
        }
    }

    return .{
        .time = 0.0,
        .offset = closest_nudge,
        .plane = closest_plane,
    };
}

pub fn traceLine(self: *Self, point: linalg.Vec3, half_extents: linalg.Vec3, direction: linalg.Vec3, ignore: PhysicsMesh.Ignore) ?PhysicsMesh.Impact {
    _ = ignore;
    return self.map.phys_mesh.traceLine(point, half_extents, direction);
}

pub fn nudge(self: *Self, point: linalg.Vec3, half_extents: linalg.Vec3, ignore: PhysicsMesh.Ignore) ?PhysicsMesh.Impact {
    var impact: ?PhysicsMesh.Impact = null;

    var new_point = point;

    for (self.entities) |*entity| {
        if (!entity.alive) continue;
        if (ignore.doesIgnoreEntity(entity)) continue;

        var new_impact = boxNudge(point, half_extents, entity.origin, entity.half_extents) orelse continue;
        new_impact.entity = entity;

        impact = new_impact.joinNudge(impact);

        new_point = point.add(impact.?.offset);
    }

    if (!ignore.map) {
        if (self.map.phys_mesh.nudge(new_point, half_extents)) |new_impact| {
            impact = new_impact.joinNudge(impact);
        }
    }

    return impact;
}
