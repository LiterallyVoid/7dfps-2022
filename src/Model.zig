const std = @import("std");

const asset = @import("./asset.zig");
const util = @import("./util.zig");
const linalg = @import("./linalg.zig");
const Mesh = @import("./Mesh.zig");
const Material = @import("./Material.zig");
const Shader = @import("./Shader.zig");
const RenderContext = @import("./RenderContext.zig");

const Self = @This();

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]i8,
    tangent: [3]i8,
    bitangent: [3]i8,
    uv: [2]f32,

    bone_indices: [4]u8,
    bone_weights: [4]u8,

    pub const Override = struct {
        pub const bone_indices = [4]Mesh.Attr_U8i;
    };
};

pub const MaterialRange = struct {
    name: []const u8,
    material: *Material,

    vertex_first: u32,
    vertex_count: u32,
};

pub const Bone = struct {
    parent: ?u32,
    name: []u8,
    rest: linalg.Mat4,
    rest_inverse: linalg.Mat4,

    rest_local: linalg.Mat4,

    frames: []const linalg.Mat4,
};

materials: []MaterialRange,
mesh: Mesh,

bones: []Bone,
bone_frames: []linalg.Mat4,
frames_count: usize,

pub const ModelFrame = struct {
    frame: f32,
    weight: f32,
};

pub fn init(am: *asset.Manager, path: []const u8) !Self {
    const file = try am.openPath(path);
    defer file.close();

    var reader = file.reader();

    var has_colors = false;

    var materials_count = try reader.readIntLittle(u32);
    if (materials_count >= 0x80000000) {
        materials_count -= 0x80000000;
        has_colors = true;
    }
    const bones_count = try reader.readIntLittle(u32);
    const frames_count = try reader.readIntLittle(u32);
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
                util.allocator.free(range_to_free.name);
                am.drop(range_to_free.material);
            }
        }

        const name_len = try reader.readIntLittle(u32);

        var name = try util.allocator.alloc(u8, name_len);
        errdefer util.allocator.free(name);

        _ = try reader.readNoEof(name);

        range.vertex_first = try reader.readIntLittle(u32);
        range.vertex_count = try reader.readIntLittle(u32);

        range.material = try am.load(Material, .{ .path = name, .options = .{ .skeletal = true } });
        errdefer am.drop(range.material);

        range.name = name;
    }

    errdefer {
        for (materials) |range_to_free| {
            util.allocator.free(range_to_free.name);
            am.drop(range_to_free.material);
        }
    }

    var bones = try util.allocator.alloc(Bone, bones_count);

    errdefer util.allocator.free(bones);
    for (bones) |*bone, i| {
        errdefer for (bones[0..i]) |bone_to_free| {
            util.allocator.free(bone_to_free.name);
        };

        const parent_id = try reader.readIntLittle(i32);
        if (parent_id >= 0) {
            bone.parent = @intCast(u32, parent_id);
        } else {
            bone.parent = null;
        }

        const name_len = try reader.readIntLittle(u32);

        var name = try util.allocator.alloc(u8, name_len);
        errdefer util.allocator.free(name);

        _ = try reader.readNoEof(name);

        for ([_]void{{}} ** 16) |_, j| {
            var bits = try reader.readIntLittle(u32);
            bone.rest_local.data[j % 4][j / 4] = @bitCast(f32, bits);
        }

        for ([_]void{{}} ** 16) |_, j| {
            var bits = try reader.readIntLittle(u32);
            bone.rest_inverse.data[j % 4][j / 4] = @bitCast(f32, bits);
        }

        bone.name = name;

        bone.frames = undefined;
    }

    errdefer for (bones) |bone| {
        util.allocator.free(bone.name);
    };

    var bone_frames = try util.allocator.alloc(linalg.Mat4, bones_count * frames_count);
    errdefer util.allocator.free(bone_frames);

    for (bones) |*bone, i| {
        const range = bone_frames[frames_count * i .. frames_count * (i + 1)];

        for (range) |*matrix| {
            for ([_]void{{}} ** 16) |_, j| {
                var bits = try reader.readIntLittle(u32);
                matrix.data[j % 4][j / 4] = @bitCast(f32, bits);
            }
        }

        bone.frames = range;
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

        if (has_colors) {
            _ = try reader.readIntLittle(u8);
            _ = try reader.readIntLittle(u8);
            _ = try reader.readIntLittle(u8);
        }

        for (vertex.uv) |*uv_elem| {
            uv_elem.* = @bitCast(f32, try reader.readIntLittle(u32));
        }

        for (vertex.bone_indices) |*bone_index| {
            bone_index.* = try reader.readIntLittle(u8);
        }

        for (vertex.bone_weights) |*bone_weight| {
            bone_weight.* = try reader.readIntLittle(u8);
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

    mesh.uploadIndices(indices);
    mesh.upload(Vertex, vertices);

    return Self{
        .materials = materials,

        .bones = bones,
        .bone_frames = bone_frames,
        .frames_count = frames_count,

        .mesh = mesh,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    for (self.materials) |range| {
        util.allocator.free(range.name);
        am.drop(range.material);
    }

    for (self.bones) |bone| {
        util.allocator.free(bone.name);
    }

    util.allocator.free(self.bones);
    util.allocator.free(self.bone_frames);

    util.allocator.free(self.materials);

    self.mesh.deinit();
}

fn calculateBones(self: Self, frames: []const ModelFrame) [64]linalg.Mat4 {
    var bones: [64]linalg.Mat4 = undefined;

    for (self.bones) |*bone, i| {
        var pose = bone.rest_local;

        if (bone.parent) |parent_id| {
            pose = pose.multiply(bones[parent_id]);
        }

        for (frames) |frame_info| {
            const frame_int = std.math.clamp(@floatToInt(usize, frame_info.frame), 0, self.frames_count - 1);
            const next_frame = std.math.clamp(frame_int + 1, 0, self.frames_count - 1);

            var frame_fraction = frame_info.frame - @intToFloat(f32, frame_int);

            var f1 = bone.frames[frame_int];
            var f2 = bone.frames[next_frame];

            var matrix = f1.multiplyScalar(1.0 - frame_fraction).addElementwise(f2.multiplyScalar(frame_fraction));

            matrix = matrix.multiplyScalar(frame_info.weight).addElementwise(linalg.Mat4.identity().multiplyScalar(1.0 - frame_info.weight));

            pose = pose.multiply(matrix);
        }

        bones[i] = pose;
    }

    for (self.bones) |*bone, i| {
        var copy = bones[i];
        bones[i] = copy.multiply(bone.rest_inverse);
    }

    return bones;
}

pub fn draw(self: Self, ctx: *RenderContext, model_matrix: linalg.Mat4, frames: []const ModelFrame) void {
    const bones = self.calculateBones(frames);

    for (self.materials) |range| {
        range.material.bind(ctx);
        range.material.shader.uniformMatrix("u_model_to_world", model_matrix);
        range.material.shader.uniformMatrices("u_bones", &bones);

        self.mesh.draw(range.vertex_first, range.vertex_count);
    }
}

pub fn drawFiltered(self: Self, ctx: *RenderContext, model_matrix: linalg.Mat4, frames: []const ModelFrame, filter: []const u8) void {
    const bones = self.calculateBones(frames);

    for (self.materials) |range| {
        if (std.mem.indexOf(u8, range.name, filter) == null) continue;

        range.material.bind(ctx);
        range.material.shader.uniformMatrix("u_model_to_world", model_matrix);
        range.material.shader.uniformMatrices("u_bones", &bones);

        self.mesh.draw(range.vertex_first, range.vertex_count);
    }
}
