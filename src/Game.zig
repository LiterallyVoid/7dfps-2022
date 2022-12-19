const std = @import("std");

const asset = @import("./asset.zig");
const c = @import("./c.zig");
const linalg = @import("./linalg.zig");
const util = @import("./util.zig");

const App = @import("./App.zig");
const Map = @import("./Map.zig");
const Entity = @import("./Entity.zig");
const RenderContext = @import("./RenderContext.zig");

const PhysicsMesh = @import("./PhysicsMesh.zig");
const Model = @import("./Model.zig");
const Texture = @import("./Texture.zig");

const Inter = @import("./Inter.zig");
const ParticleMonster = @import("./ParticleMonster.zig");
const Sound = @import("./Sound.zig");

const ent_player = @import("./entities/player.zig");
const ent_slasher = @import("./entities/slasher.zig");
const ent_gunner = @import("./entities/gunner.zig");

const Self = @This();

const MAXENTITIES = 1024;

pub const Input = struct {
    const Key = enum(u32) {
        jump,
        attack,
        reload,
        quick_melee,
    };

    angle: [2]f32 = .{ 0.0, 0.0 }, // pitch, yaw

    movement: [2]f32 = .{ 0.0, 0.0 },

    keys_held: [4]bool = [1]bool{false} ** 4,
    keys_pressed: [4]bool = [1]bool{false} ** 4,

    pub fn keyHeld(self: Input, k: Key) bool {
        return self.keys_held[@enumToInt(k)];
    }

    pub fn keyPressed(self: Input, k: Key) bool {
        return self.keys_pressed[@enumToInt(k)];
    }
};

app: *App,

asset_manager: *asset.Manager,
map: *Map,
entities: [MAXENTITIES]Entity,
player: *Entity,

prng: std.rand.DefaultPrng,
rand: std.rand.Random,

particles: ParticleMonster,

dbg_gizmo: *Model,

crosshair_tex: *Texture,
sound_shoot: *Sound,
sound_chaingun_shoot: *Sound,
sound_shotgun_mech: *Sound,
sound_hit: *Sound,
sound_murder: *Sound,
sound_melee_hit: *Sound,

victory_time: f32 = 0.0,

pub fn init(self: *Self, app: *App, am: *asset.Manager, map: []const u8) !void {
    self.* = .{
        .app = app,
        .asset_manager = am,
        .map = try am.load(Map, map),
        .entities = [1]Entity{.{}} ** MAXENTITIES,
        .player = undefined,

        .prng = std.rand.DefaultPrng.init(1337),
        .rand = undefined,

        .particles = undefined,

        .dbg_gizmo = try am.load(Model, "dev/gizmo.model"),
        .crosshair_tex = try am.load(Texture, "special/crosshair/crosshair.png"),
        .sound_shoot = try am.load(Sound, "sounds/shotgun-fire.ogg"),
        .sound_chaingun_shoot = try am.load(Sound, "sounds/chaingun-fire.ogg"),
        .sound_shotgun_mech = try am.load(Sound, "sounds/shotgun-mech.ogg"),
        .sound_hit = try am.load(Sound, "sounds/hit.ogg"),
        .sound_murder = try am.load(Sound, "sounds/murder.ogg"),
        .sound_melee_hit = try am.load(Sound, "sounds/melee-hit.ogg"),
    };

    try self.particles.init(am);

    self.rand = self.prng.random();

    self.player = undefined;

    for (self.map.entities) |entity| {
        const ent = self.spawn().?;

        switch (entity.kind) {
            .slasher => ent_slasher.spawn(ent, self),
            .gunner => ent_gunner.spawn(ent, self),
            .coin => ent_gunner.spawn(ent, self),
            .player => {
                ent_player.spawn(ent, self);
                self.player = ent;
            },
        }

        ent.origin = entity.position;
        ent.angle.data[2] = entity.angle + std.math.pi;
        ent.origin.data[2] += ent.half_extents.data[2];

        if (ent.traceVertical(&Entity.TickContext {.game = self, .delta = 0}, -3.0)) |offset| {
            ent.origin.data[2] += offset;
        }
    }
}

pub fn deinit(self: *Self) void {
    for (self.entities) |entity| {
        for (entity.models) |model_opt| {
            const model = model_opt orelse continue;
            self.asset_manager.drop(model);
        }
    }

    self.particles.deinit(self.asset_manager);

    self.asset_manager.drop(self.map);
    self.asset_manager.drop(self.dbg_gizmo);
    self.asset_manager.drop(self.crosshair_tex);
    self.asset_manager.drop(self.sound_shoot);
    self.asset_manager.drop(self.sound_chaingun_shoot);
    self.asset_manager.drop(self.sound_shotgun_mech);
    self.asset_manager.drop(self.sound_hit);
    self.asset_manager.drop(self.sound_murder);
    self.asset_manager.drop(self.sound_melee_hit);
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
    self.particles.tick(delta);

    var ctx = Entity.TickContext{
        .game = self,
        .delta = std.math.min(delta, 1.0 / 15.0),
    };

    var enemies_alive = false;

    for (self.entities) |*entity| {
        if (!entity.alive) {
            for (entity.models) |*model_opt| {
                const model = model_opt.* orelse continue;

                self.asset_manager.drop(model);

                model_opt.* = null;
            }

            continue;
        }

        if (entity.team == .enemy) enemies_alive = true;

        entity.tick(entity, &ctx);
    }

    if (enemies_alive) self.victory_time += delta;
}

fn mainDraw(self: *Self, ctx: *RenderContext) void {
    self.map.draw(ctx);

    for (self.entities) |*entity| {
        if (!entity.alive) continue;
        if (entity == self.player) continue;

        entity.draw(entity, self, ctx);
    }
}

pub fn drawShadow(self: *Self, ctx: *RenderContext) void {
    ctx.matrix_world_to_camera = linalg.Mat4.identity();
    ctx.matrix_camera_to_world = linalg.Mat4.identity();

    ctx.matrix_projection = linalg.Mat4.orthographic(-100.0, 100.0, -100.0, 100.0, -100.0, 100.0);
    const SUN_DIR = linalg.Vec3.new(0.15, 0.4, 1.0).normalized();

    ctx.matrix_projection = ctx.matrix_projection.multiply(linalg.Mat4.lookAt(SUN_DIR, linalg.Vec3.new(0.0, 0.0, 0.0), linalg.Vec3.new(0.0, 0.0, 1.0)));

    ctx.matrix_shadow = ctx.matrix_projection;

    mainDraw(self, ctx);
}

pub fn draw(self: *Self, ctx: *RenderContext) void {
    c.glEnable(c.GL_CULL_FACE);

    c.glDepthRange(0.0, 1.0);

    self.player.camera(self.player, self, ctx);
    mainDraw(self, ctx);

    if (self.player.alive) self.player.draw(self.player, self, ctx);
}

pub fn drawTransparent(self: *Self, ctx: *RenderContext) void {
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glDepthMask(c.GL_FALSE);
    self.map.drawTransparent(ctx);

    self.particles.draw(ctx);

    for (self.entities) |*entity| {
        if (!entity.alive) continue;
        if (entity == self.player) continue;

        entity.drawTransparent(entity, self, ctx);
    }

    if (self.player.alive) self.player.drawTransparent(self.player, self, ctx);

    c.glDisable(c.GL_BLEND);
    c.glDepthMask(c.GL_TRUE);
}

pub fn drawUI(self: *Self, into: *Inter.Viewport) void {
    into.anchor();
    if (self.player.alive) self.player.drawUI(self.player, self, into);
}

fn boxTraceLine(point: linalg.Vec3, half_extents: linalg.Vec3, direction: linalg.Vec3, ent_origin: linalg.Vec3, ent_half_extents: linalg.Vec3) ?PhysicsMesh.Impact {
    var enter_time = -std.math.inf(f32);
    var exit_time = std.math.inf(f32);

    var enter_plane: linalg.Vec4 = undefined;

    comptime var i: usize = 0;
    inline while (i < 6) : (i += 1) blk: {
        const axis = i % 3;

        var sign: f32 = if (i < 3) 1.0 else -1.0;

        var plane = linalg.Vec4.zero();
        plane.data[axis] = sign;
        plane.data[3] = ent_origin.data[axis] * -sign - ent_half_extents.data[axis];

        var height = (point.data[axis] - ent_origin.data[axis]) * sign - ent_half_extents.data[axis] - half_extents.data[axis];
        var speed = direction.data[axis] * sign;

        if (speed == 0.0) {
            if (height < 0) break :blk;
            return null;
        }

        var time = height / -speed;

        if (speed > 0.0) {
            exit_time = std.math.min(exit_time, time);
            break :blk;
        }

        if (time > enter_time) {
            enter_time = time;
            enter_plane = plane;
        }

        if (enter_time > exit_time + 0.00001) return null;
    }

    if (enter_time < 0.0) return null;
    if (enter_time > 1.0) return null;
    if (enter_time > exit_time + 0.00001) return null;

    return .{
        .time = enter_time,
        .plane = enter_plane,
    };
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
    var impact: ?PhysicsMesh.Impact = null;

    for (self.entities) |*entity| {
        if (!entity.alive) continue;
        if (ignore.doesIgnoreEntity(entity)) continue;

        var new_impact = boxTraceLine(point, half_extents, direction, entity.origin, entity.half_extents) orelse continue;
        new_impact.entity = entity;

        impact = new_impact.join(impact);
    }

    if (self.map.phys_mesh.traceLine(point, half_extents, direction)) |new_impact| {
        impact = new_impact.join(impact);
    }

    return impact;
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
