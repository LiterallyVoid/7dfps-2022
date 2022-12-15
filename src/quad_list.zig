const std = @import("std");

const linalg = @import("./linalg.zig");
const util = @import("./util.zig");
const asset = @import("./asset.zig");
const Shader = @import("./Shader.zig");
const Mesh = @import("./Mesh.zig");
const Texture = @import("./Texture.zig");
const Font = @import("./Font.zig");
const RenderContext = @import("./RenderContext.zig");

pub fn QuadList(comptime Vertex: type) type {
    return struct {
        const Self = @This();

        mesh: Mesh,

        vertices: [1024]Vertex,
        vertices_count: usize,

        texture: ?Texture,

        pub fn init() Self {
            return Self{
                .mesh = Mesh.init(.{ .static = false, .indexed = false }, Vertex),

                .vertices = undefined,
                .vertices_count = 0,

                .texture = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.mesh.deinit();
        }

        pub fn addVertices(self: *Self, vertices: []const Vertex) void {
            if ((self.vertices_count + vertices.len) > 1020) {
                self.flush();
            }

            for (vertices) |vert| {
                self.vertices[self.vertices_count] = vert;

                self.vertices_count += 1;
            }
        }

        pub fn addQuad(self: *Self, vertices: [4]Vertex) void {
            const to_append = [_]Vertex{
                vertices[0],
                vertices[1],
                vertices[3],
                vertices[3],
                vertices[2],
                vertices[0],
            };

            self.addVertices(&to_append);
        }

        pub fn flush(self: *Self) void {
            if (self.vertices_count == 0) return;

            if (self.texture) |tex| {
                tex.bind(0);
            }

            self.mesh.upload(Vertex, self.vertices[0..self.vertices_count]);
            self.mesh.draw(0, self.vertices_count);

            self.vertices_count = 0;
        }
    };
}
