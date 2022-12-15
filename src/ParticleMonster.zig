const std = @import("std");

const asset = @import("./asset.zig");
const c = @import("./c.zig");
const linalg = @import("./linalg.zig");
const util = @import("./util.zig");

const Mesh = @import("./Mesh.zig");
const Shader = @import("./Shader.zig");
const Texture = @import("./Texture.zig");

const RenderContext = @import("./RenderContext.zig");

const Self = @This();

const ATLAS_CELLS = 8;
const ATLAS_CELLS_F = @intToFloat(f32, ATLAS_CELLS);

const ParticleDefinition = struct {
    spawn_jitter: f32 = 0.0,

    count: u32 = 1,
    spawn_interval: f32 = -1.0,

    lifetime: [2]f32 = .{ 1.0, 1.0 },

    velocity_intrinsic: [2]f32 = .{ 0.0, 0.0 },
    velocity_random: f32 = 0.0,

    offset_intrinsic: f32 = 0.0,

    gravity: f32 = 0.0,

    texture_1: [4]u8 = .{ 0, 0, 1, 1 },
    texture_2: [4]u8 = .{ 0, 0, 1, 1 },

    size_start: [2]f32 = .{ 1.0, 1.0 },
    size_end: [2]f32 = .{ 1.0, 1.0 },

    size_curve: f32 = 1.0,

    drag_start: [2]f32 = .{ 0.0, 0.0 },
    drag_end: [2]f32 = .{ 0.0, 0.0 },

    color_start: [2]linalg.Vec4 = .{
        linalg.Vec4.broadcast(1.0),
        linalg.Vec4.broadcast(1.0),
    },
    color_end: [2]linalg.Vec4 = .{
        linalg.Vec4.broadcast(1.0),
        linalg.Vec4.broadcast(1.0),
    },

    stretch: f32 = -1.0,

    fade: [2]f32 = .{ 0.0, 0.0 },

    pub fn instantiate(self: ParticleDefinition, effect: *Effect, rand: std.rand.Random, position: linalg.Vec3) Particle {
        var offset = linalg.Vec3.new(2.0, 0.0, 0.0);
        while (!offset.smallerThan(1.0)) {
            offset = linalg.Vec3.new(
                rand.float(f32) * 2.0 - 1.0,
                rand.float(f32) * 2.0 - 1.0,
                rand.float(f32) * 2.0 - 1.0,
            );
        }

        var velocity = linalg.Vec3.new(2.0, 0.0, 0.0);
        while (!velocity.smallerThan(1.0)) {
            velocity = linalg.Vec3.new(
                rand.float(f32) * 2.0 - 1.0,
                rand.float(f32) * 2.0 - 1.0,
                rand.float(f32) * 2.0 - 1.0,
            );
        }

        const lifetime = linalg.mix(
            self.lifetime[0],
            self.lifetime[1],
            rand.float(f32),
        );

        const velocity_intrinsic = linalg.mix(
            self.velocity_intrinsic[0],
            self.velocity_intrinsic[1],
            rand.float(f32),
        );

        const size_start = linalg.mix(
            self.size_start[0],
            self.size_start[1],
            rand.float(f32),
        );

        const size_end = linalg.mix(
            self.size_end[0],
            self.size_end[1],
            rand.float(f32),
        );

        const drag_start = linalg.mix(
            self.drag_start[0],
            self.drag_start[1],
            rand.float(f32),
        );

        const drag_end = linalg.mix(
            self.drag_end[0],
            self.drag_end[1],
            rand.float(f32),
        );

        const color_start =
            self.color_start[0]
            .mix(self.color_start[1], rand.float(f32))
            .mulScalar(255.0)
            .toArray(u8);

        const color_end =
            self.color_end[0]
            .mix(self.color_end[0], rand.float(f32))
            .mulScalar(255.0)
            .toArray(u8);

        const fade = linalg.mix(
            self.fade[0],
            self.fade[1],
            rand.float(f32),
        );

        return Particle{
            .lifetime = lifetime,

            .position = position.add(offset.mulScalar(self.spawn_jitter)).add(effect.direction.mulScalar(self.offset_intrinsic)),
            .velocity = effect.direction.mulScalar(velocity_intrinsic).add(velocity.mulScalar(self.velocity_random)),

            .gravity = self.gravity,

            .texture_1 = self.texture_1,
            .texture_2 = self.texture_2,

            .size_start = size_start,
            .size_end = size_end,

            .size_curve = self.size_curve,

            .drag_start = drag_start,
            .drag_end = drag_end,

            .color_start = color_start,
            .color_end = color_end,

            .stretch = self.stretch,
            .fade = fade,
        };
    }
};

const TrailDefinition = struct {
    particle: ParticleDefinition = .{},
};

const EffectDefinition = struct {
    trails: std.ArrayListUnmanaged(TrailDefinition) = .{},
    particles: std.ArrayListUnmanaged(ParticleDefinition) = .{},
};

const Vertex = struct {
    position: [3]f32,
    color: [4]u8,

    uv: [2]u16,
    uv2: [2]u16,
};

const QuadList = @import("./quad_list.zig").QuadList(Vertex);

const Particle = struct {
    current_time: f32 = 0.0,
    lifetime: f32,

    texture_1: [4]u8,
    texture_2: [4]u8,

    position: linalg.Vec3,
    velocity: linalg.Vec3,

    gravity: f32,

    size_start: f32,
    size_end: f32,

    size_curve: f32,

    color_start: [4]u8,
    color_end: [4]u8,

    drag_start: f32,
    drag_end: f32,

    stretch: f32,
    fade: f32,

    fn tick(self: *Particle, delta: f32) void {
        self.current_time += delta / self.lifetime;
        self.position = self.position.add(self.velocity.mulScalar(delta));

        const drag = linalg.mix(self.drag_start, self.drag_end, self.current_time);

        self.velocity = self.velocity.mulScalar(std.math.exp(-delta * drag));

        self.velocity.data[2] -= self.gravity * delta * 30.0;
    }

    fn setUvs(x: usize, y: usize, uvs: *[2]u16, texture: [4]u8) void {
        var grid_x = @intToFloat(f32, texture[0] + @intCast(u8, x) * texture[2]);
        var grid_y = @intToFloat(f32, texture[1] + @intCast(u8, y) * texture[3]);

        const margin = 0.05;

        if (x == 0) {
            grid_x += margin;
        } else {
            grid_x -= margin;
        }

        if (y == 0) {
            grid_y += margin;
        } else {
            grid_y -= margin;
        }

        uvs.* = .{ @floatToInt(u16, grid_x / ATLAS_CELLS_F * 65535.0), @floatToInt(u16, grid_y / ATLAS_CELLS_F * 65535.0) };

    }

    fn drawFlat(self: *Particle, into: *QuadList, color: [4]u8, half_size: f32, camera_position: linalg.Vec3, camera_directions: [3]linalg.Vec3) void {
        _ = camera_position;

        var vertices: [4]Vertex = undefined;

        for (vertices) |*vertex, i| {
            var x = i % 2;
            var y = i / 2;

            var x_sign: f32 = if (x == 1) 1.0 else -1.0;
            var y_sign: f32 = if (y == 1) 1.0 else -1.0;

            vertex.position = self.position
                .add(camera_directions[2].mulScalar(-half_size))
                .add(camera_directions[0].mulScalar(half_size * x_sign))
                .add(camera_directions[1].mulScalar(half_size * y_sign))
                .toArray(f32);

            vertex.color = color;

            setUvs(x, y, &vertex.uv, self.texture_1);
            setUvs(x, y, &vertex.uv2, self.texture_2);
        }

        into.addQuad(vertices);
    }

    fn drawStretched(self: *Particle, into: *QuadList, color: [4]u8, half_size: f32, camera_position: linalg.Vec3, camera_directions: [3]linalg.Vec3) void {
        var vertices: [4]Vertex = undefined;

        var stretch_vec = self.velocity.mulScalar(self.stretch * 0.5);
        const side_vec = (self.position.sub(camera_position)).cross(stretch_vec).normalized().mulScalar(half_size);

        stretch_vec = stretch_vec.add(side_vec.cross(camera_directions[2]).mulScalar(half_size));

        for (vertices) |*vertex, i| {
            var x = i / 2;
            var y = i % 2;

            var x_sign: f32 = @intToFloat(f32, x) * 2.0 - 1.0;
            var y_sign: f32 = @intToFloat(f32, y) * 2.0 - 1.0;

            vertex.position = self.position
                .add(camera_directions[2].mulScalar(-half_size))
                .add(stretch_vec.mulScalar(x_sign))
                .add(side_vec.mulScalar(y_sign))
                .toArray(f32);

            vertex.color = color;

            setUvs(x, y, &vertex.uv, self.texture_1);
            setUvs(x, y, &vertex.uv2, self.texture_2);
        }

        into.addQuad(vertices);
    }

    fn draw(self: *Particle, into: *QuadList, camera_position: linalg.Vec3, camera_directions: [3]linalg.Vec3) void {
        const BVec4 = linalg.Vector(4, u8, null);

        var fade = if (self.current_time > 1.0 - self.fade)
            1.0 - (((1.0 - self.current_time) / self.fade))
        else
            0.0;

        const color =
            BVec4.fromArray(u8, self.color_start)
            .mixInt(BVec4.fromArray(u8, self.color_end), self.current_time)
            .mixInt(BVec4.zero(), fade)
            .toArray(u8);

        const half_size = linalg.mix(
            self.size_start,
            self.size_end,
            std.math.pow(f32, self.current_time, self.size_curve),
        ) * 0.5;

        if (self.stretch > 0.0) {
            self.drawStretched(into, color, half_size, camera_position, camera_directions);
        } else {
            self.drawFlat(into, color, half_size, camera_position, camera_directions);
        }
    }
};

const Trail = struct {
    definition: *TrailDefinition,

    length: f32 = 0.0,

    points: std.ArrayListUnmanaged(Particle) = .{},

    fn deinit(self: *Trail) void {
        self.points.deinit(util.allocator);
    }

    fn tick(self: *Trail, delta: f32) void {
        for (self.points.items) |*particle| {
            particle.tick(delta);
        }
    }

    fn draw(self: *Trail, into: *QuadList) void {
        _ = self;
        _ = into;
    }
};

pub const Effect = struct {
    def: *EffectDefinition,

    position: linalg.Vec3,
    direction: linalg.Vec3,

    trails: []Trail,

    fn create(def: *EffectDefinition) !*Effect {
        const effect = try util.allocator.create(Effect);

        effect.def = def;

        effect.trails = &.{};

        if (def.trails.items.len > 0) {
            effect.trails = try util.allocator.alloc(Trail, def.trails.items.len);
            for (effect.trails) |*trail, i| {
                trail.* = .{
                    .definition = &def.trails.items[i],
                };
            }
        }

        return effect;
    }

    fn spawnParticles(self: *Effect, pmon: *Self, position: linalg.Vec3) !void {
        for (self.def.particles.items) |particle_def| {
            var i: u32 = 0;
            while (i < particle_def.count) : (i += 1) {
                const particle = particle_def.instantiate(self, pmon.random, position);
                try pmon.particles.append(particle);
            }
        }
    }
};

effect_definitions: std.StringHashMap(EffectDefinition),

effects: std.AutoHashMap(*Effect, void),
particles: std.ArrayList(Particle),
fading_trails: std.ArrayList(Trail),

rng: std.rand.DefaultPrng,
random: std.rand.Random,

shader: *Shader,
texture: *Texture,
quads: QuadList,

fn parseProperty(comptime T: type, into: ?*T, kwd: []const u8, numbers: []f32) !bool {
    var found: bool = false;

    inline for (@typeInfo(T).Struct.fields) |field| outer: {
        if (!std.mem.eql(u8, kwd, field.name)) break :outer;

        @field(into.?, field.name) = switch (field.field_type) {
            f32 => blk: {
                if (numbers.len != 1) {
                    std.log.err("expected one number", .{});
                }

                break :blk numbers[0];
            },
            u32 => blk: {
                if (numbers.len != 1) {
                    std.log.err("expected one number", .{});
                }

                break :blk @floatToInt(u32, numbers[0]);
            },
            [2]f32 => blk: {
                if (numbers.len == 1) {
                    break :blk .{
                        numbers[0],
                        numbers[0],
                    };
                } else if (numbers.len == 2) {
                    break :blk .{
                        numbers[0],
                        numbers[1],
                    };
                } else {
                    std.log.err("expected one or two number", .{});
                }
            },
            [4]u8 => blk: {
                if (numbers.len != 4) {
                    std.log.err("expected four numbers", .{});
                }

                break :blk .{
                    @floatToInt(u8, numbers[0]),
                    @floatToInt(u8, numbers[1]),
                    @floatToInt(u8, numbers[2]),
                    @floatToInt(u8, numbers[3]),
                };
            },
            [2]linalg.Vec4 => blk: {
                if (numbers.len != 4 and numbers.len != 8) {
                    std.log.err("expected four or eight numbers", .{});
                }

                var first = linalg.Vec4.new(
                    numbers[0],
                    numbers[1],
                    numbers[2],
                    numbers[3],
                );

                var second = first;

                if (numbers.len == 8) {
                    second = linalg.Vec4.new(
                        numbers[4],
                        numbers[5],
                        numbers[6],
                        numbers[7],
                    );
                }

                break :blk .{ first, second };
            },
            else => unreachable,
        };

        found = true;
    }

    return found;
}

fn parseDefinitions(contents: []const u8) !std.StringHashMap(EffectDefinition) {
    // get rid of the memory leak diagnostics!
    errdefer @panic("no leaks here stop looking");

    var effects = std.StringHashMap(EffectDefinition).init(util.allocator);

    var lines = std.mem.tokenize(u8, contents, "\n");

    var lineno: usize = 0;

    var effect: ?*EffectDefinition = null;
    var trail: ?*TrailDefinition = null;
    var particle: ?*ParticleDefinition = null;

    while (lines.next()) |line_| {
        var line = std.mem.trim(u8, line_, "\r\n\t ");
        lineno += 1;

        if (line[0] == '#') continue;

        errdefer {
            std.log.err("error while parsing line {} of effects.txt", .{lineno});
            std.log.err("line: {s}", .{line});
        }

        if (line.len == 0) continue;

        var tokens = std.mem.tokenize(u8, line, " \t");

        const kwd = tokens.next() orelse return error.NoKeyword;

        if (std.mem.eql(u8, kwd, "effect")) {
            const name = tokens.next() orelse return error.NoName;

            try effects.put(try util.allocator.dupe(u8, name), .{});

            effect = effects.getEntry(name).?.value_ptr;

            trail = null;
            particle = null;
            continue;
        }

        var numbers: [16]f32 = undefined;
        var numbers_len: usize = 0;

        for (numbers) |*number| {
            const token = tokens.next() orelse break;

            number.* = std.fmt.parseFloat(f32, token) catch break;
            numbers_len += 1;
        }

        errdefer {
            std.log.err("have {} numbers", .{numbers_len});
        }

        if (std.mem.eql(u8, kwd, "particle")) {
            try effect.?.particles.append(util.allocator, .{});
            particle = &effect.?.particles.items[effect.?.particles.items.len - 1];
            trail = null;
        } else if (std.mem.eql(u8, kwd, "trail")) {
            try effect.?.trails.append(util.allocator, .{});
            trail = &effect.?.trails.items[effect.?.trails.items.len - 1];
            particle = &trail.?.particle;
        } else {
            if (try parseProperty(ParticleDefinition, particle, kwd, numbers[0..numbers_len])) continue;
            if (try parseProperty(TrailDefinition, trail, kwd, numbers[0..numbers_len])) continue;

            std.log.err("unknown keyword [{s}]", .{kwd});
            return error.UnknownKeyword;
        }
    }

    return effects;
}

pub fn init(self: *Self, am: *asset.Manager) !void {
    const defs_file = try am.openPath("effects.txt");
    defer defs_file.close();

    const data = try defs_file.reader().readAllAlloc(util.allocator, 16 * 1024 * 1024);
    defer util.allocator.free(data);

    const effect_definitions = try parseDefinitions(data);

    self.* = .{
        .rng = std.rand.DefaultPrng.init(1338),
        .random = undefined,

        .effect_definitions = effect_definitions,

        .effects = std.AutoHashMap(*Effect, void).init(util.allocator),
        .particles = std.ArrayList(Particle).init(util.allocator),
        .fading_trails = std.ArrayList(Trail).init(util.allocator),

        .shader = try am.load(Shader, "shaders/particles"),
        .texture = try am.load(Texture, "particles/sheet.png"),
        .quads = QuadList.init(),
    };

    self.random = self.rng.random();
}

pub fn deinit(self: *Self, am: *asset.Manager) void {
    var effect_defs_it = self.effect_definitions.iterator();
    while (effect_defs_it.next()) |effect_def| {
        effect_def.value_ptr.trails.deinit(util.allocator);
        effect_def.value_ptr.particles.deinit(util.allocator);

        util.allocator.free(effect_def.key_ptr.*);
    }

    self.effect_definitions.deinit();

    var effects_it = self.effects.iterator();
    while (effects_it.next()) |effect| {
        for (effect.key_ptr.*.trails) |*trail| {
            trail.deinit();
        }

        util.allocator.free(effect.key_ptr.*.trails);
    }

    self.effects.deinit();
    self.particles.deinit();
    self.fading_trails.deinit();

    am.drop(self.shader);
    am.drop(self.texture);
}

pub fn effectHeld(self: *Self, name: []const u8, position: linalg.Vec3, direction: linalg.Vec3) !*Effect {
    const definition_entry = self.effect_definitions.getEntry(name) orelse return error.NoSuchEffect;

    const effect = try Effect.create(definition_entry.value_ptr);

    effect.position = position;
    effect.direction = direction;

    try self.effects.put(effect, {});

    try effect.spawnParticles(self, position);

    return effect;
}

pub fn effectOne(self: *Self, name: []const u8, position: linalg.Vec3, direction: linalg.Vec3) !void {
    const effect = try self.effectHeld(name, position, direction);
    self.dropEffect(effect);
}

pub fn dropEffect(self: *Self, effect: *Effect) void {
    for (effect.trails) |*trail| {
        self.fading_trails.append(trail.*) catch {
            trail.deinit();
        };
    }

    util.allocator.free(effect.trails);

    _ = self.effects.remove(effect);

    util.allocator.destroy(effect);
}

pub fn tick(self: *Self, delta: f32) void {
    var i: usize = 0;
    while (i < self.particles.items.len) {
        const particle = &self.particles.items[i];

        particle.tick(delta);

        if (particle.current_time > 1.0) {
            _ = self.particles.swapRemove(i);
        } else {
            i += 1;
        }
    }

    for (self.fading_trails.items) |*trail| {
        trail.tick(delta);
    }
}

fn particleCompare(camera_position: linalg.Vec3, a: Particle, b: Particle) bool {
    return a.position.sub(camera_position).lengthSquared() >
        b.position.sub(camera_position).lengthSquared();
}

pub fn draw(self: *Self, context: *RenderContext) void {
    self.shader.bind(context);
    self.shader.uniformTexture("u_texture", 0, self.texture.*);
    defer self.quads.flush();

    var camera_matrix = context.matrix_world_to_camera.toMat3();

    var camera_position = context.camera_position();

    var camera_directions = .{
        camera_matrix.multiplyVector(linalg.Vec3.new(1.0, 0.0, 0.0)),
        camera_matrix.multiplyVector(linalg.Vec3.new(0.0, 1.0, 0.0)),
        camera_matrix.multiplyVector(linalg.Vec3.new(0.0, 0.0, -1.0)),
    };

    std.sort.sort(Particle, self.particles.items, camera_position, particleCompare);

    for (self.particles.items) |*particle| {
        particle.draw(&self.quads, camera_position, camera_directions);
    }
}
