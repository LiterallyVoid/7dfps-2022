const std = @import("std");

const asset = @import("./asset.zig");
const util = @import("./util.zig");
const linalg = @import("./linalg.zig");
const Mesh = @import("./Mesh.zig");
const Material = @import("./Material.zig");
const RenderContext = @import("./RenderContext.zig");
const PhysicsMesh = @import("./PhysicsMesh.zig");

const Self = @This();

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]i8,
    tangent: [3]i8,
    bitangent: [3]i8,
    uv: [2]f32,
};

pub const MaterialRange = struct {
    material: *Material,

    vertex_first: u32,
    vertex_count: u32,
};

pub const Entity = struct {
    pub const Kind = enum {
        slasher,
        gunner,
        coin,
        player,
    };
    kind: Kind,
    position: linalg.Vec3,
    angle: f32,
};

entities: []Entity,
materials: []MaterialRange,
mesh: Mesh,

phys_mesh: PhysicsMesh,

pub fn init(am: *asset.Manager, path: []const u8) !Self {
    const file = try am.openPath(path);
    defer file.close();

    var reader = file.reader();

    const materials_count = try reader.readIntLittle(u32);
    const entities_count = try reader.readIntLittle(u32);
    const indices_count = try reader.readIntLittle(u32);
    const vertices_count = try reader.readIntLittle(u32);

    var mesh = Mesh.init(
        .{
            .static = true,
            .indexed = true,
        },
        Vertex,
    );
    errdefer mesh.deinit();

    var materials = try util.allocator.alloc(MaterialRange, materials_count);
    errdefer util.allocator.free(materials);
    for (materials) |*range, i| {
        errdefer {
            for (materials[0..i]) |range_to_free| {
                am.drop(range_to_free.material);
            }
        }

        const name_len = try reader.readIntLittle(u32);

        var name = try util.allocator.alloc(u8, name_len);
        defer util.allocator.free(name);

        _ = try reader.readNoEof(name);

        range.vertex_first = try reader.readIntLittle(u32);
        range.vertex_count = try reader.readIntLittle(u32);

        if (std.mem.indexOf(u8, name, "noclip")) |_| {
            range.material = try am.load(Material, .{ .path = "textures/grid.png" });
            range.vertex_count = 0;
        } else {
            range.material = try am.load(Material, .{ .path = name });
        }
    }

    errdefer {
        for (materials) |range_to_free| {
            am.drop(range_to_free.material);
        }
    }

    var indices = try util.allocator.alloc(u32, indices_count);
    defer util.allocator.free(indices);

    for (indices) |*index| {
        index.* = try reader.readIntLittle(u32);
    }

    var vertices = try util.allocator.alloc(Vertex, vertices_count);
    defer util.allocator.free(vertices);

    for (vertices) |*vertex| {
        for (vertex.position) |*pos_elem| {
            pos_elem.* = @bitCast(f32, try reader.readIntLittle(u32));
        }

        for (vertex.normal) |*norm_elem| {
            norm_elem.* = try reader.readIntLittle(i8);
        }

        for (vertex.tangent) |*elem| {
            elem.* = try reader.readIntLittle(i8);
        }

        for (vertex.bitangent) |*elem| {
            elem.* = try reader.readIntLittle(i8);
        }

        for (vertex.uv) |*uv_elem| {
            uv_elem.* = @bitCast(f32, try reader.readIntLittle(u32));
        }
    }

    var triangles = try util.allocator.alloc([3][3]f32, indices_count / 3);
    defer util.allocator.free(triangles);

    for (triangles) |*triangle, i| {
        triangle.* = .{
            vertices[indices[i * 3]].position,
            vertices[indices[i * 3 + 1]].position,
            vertices[indices[i * 3 + 2]].position,
        };
    }

    var entities = try util.allocator.alloc(Entity, entities_count);
    for (entities) |*entity| {
        entity.* = .{
            .kind = @intToEnum(Entity.Kind, try reader.readIntLittle(u32)),
            .position = linalg.Vec3.new(
                @bitCast(f32, try reader.readIntLittle(u32)),
                @bitCast(f32, try reader.readIntLittle(u32)),
                @bitCast(f32, try reader.readIntLittle(u32)),
            ),
            .angle = @bitCast(f32, try reader.readIntLittle(u32)),
        };
    }

    const phys_mesh = try PhysicsMesh.init(triangles);

    mesh.uploadIndices(indices);
    mesh.upload(Vertex, vertices);

    return Self{
        .materials = materials,
        .entities = entities,
        .mesh = mesh,
        .phys_mesh = phys_mesh,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    for (self.materials) |range| {
        am.drop(range.material);
    }

    util.allocator.free(self.materials);

    self.mesh.deinit();
    self.phys_mesh.deinit();
    util.allocator.free(self.entities);
}

pub fn draw(self: Self, ctx: *RenderContext) void {
    for (self.materials) |range| {
        if (range.material.transparent) continue;
        range.material.bind(ctx);

        self.mesh.draw(range.vertex_first, range.vertex_count);
    }
}

pub fn drawTransparent(self: Self, ctx: *RenderContext) void {
    for (self.materials) |range| {
        if (!range.material.transparent) continue;
        range.material.bind(ctx);

        self.mesh.draw(range.vertex_first, range.vertex_count);
    }
}
