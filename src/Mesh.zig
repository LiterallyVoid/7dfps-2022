const std = @import("std");

const c = @import("./c.zig");

const Self = @This();

pub const IndexType = u32;

pub const Config = struct {
    static: bool,
    indexed: bool,
};

config: Config,

gl_vbo: c.GLuint,
gl_ibo: c.GLuint,
gl_vao: c.GLuint,

pub fn init(config: Config, comptime Vertex: type) Self {
    var self = Self{
        .config = config,

        .gl_vbo = undefined,
        .gl_ibo = undefined,
        .gl_vao = undefined,
    };

    c.glGenVertexArrays(1, &self.gl_vao);
    c.glBindVertexArray(self.gl_vao);

    c.glGenBuffers(1, &self.gl_vbo);
    c.glGenBuffers(1, &self.gl_ibo);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, self.gl_vbo);

    inline for (@typeInfo(Vertex).Struct.fields) |field, i| {
        c.glEnableVertexAttribArray(i);

        const Inner = @typeInfo(field.field_type).Array.child;

        const vec_len = @typeInfo(field.field_type).Array.len;
        const vec_ty = switch (Inner) {
            i8 => c.GL_BYTE,
            u8 => c.GL_UNSIGNED_BYTE,

            i32 => c.GL_INT,
            u32 => c.GL_UNSIGNED_INT,

            f32 => c.GL_FLOAT,

            else => unreachable,
        };

        const normalize = switch (Inner) {
            f32 => c.GL_FALSE,
            f64 => c.GL_FALSE,

            else => c.GL_TRUE,
        };

        c.glVertexAttribPointer(i, vec_len, vec_ty, normalize, @sizeOf(Vertex), @intToPtr(?*anyopaque, @offsetOf(Vertex, field.name)));
    }

    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.gl_ibo);

    return self;
}

pub fn deinit(self: Self) void {
    c.glDeleteBuffers(1, &self.gl_vbo);
    c.glDeleteBuffers(1, &self.gl_ibo);

    c.glDeleteVertexArrays(1, &self.gl_vao);
}

pub fn upload(self: Self, comptime Vertex: type, vertices: []const Vertex) void {
    const usage: c.GLuint = if (self.config.static)
        c.GL_STATIC_DRAW
    else
        c.GL_STREAM_DRAW;

    c.glBindBuffer(c.GL_ARRAY_BUFFER, self.gl_vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, @sizeOf(Vertex) * vertices.len), vertices.ptr, usage);
}

pub fn uploadIndices(self: Self, indices: []const IndexType) void {
    std.debug.assert(self.config.indexed);

    const usage: c.GLuint = if (self.config.static)
        c.GL_STATIC_DRAW
    else
        c.GL_STREAM_DRAW;

    // Necessary, because otherwise we'd be assigning to the current index
    // buffer for some random vertex array!
    c.glBindVertexArray(self.gl_vao);

    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.gl_ibo);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(c_long, @sizeOf(IndexType) * indices.len), indices.ptr, usage);
}

pub fn draw(self: Self, first: usize, count: usize) void {
    c.glBindVertexArray(self.gl_vao);

    if (self.config.indexed) {
        std.debug.assert(IndexType == u32);

        c.glDrawElements(c.GL_TRIANGLES, @intCast(c_int, count), c.GL_UNSIGNED_INT, @intToPtr(?*anyopaque, @sizeOf(IndexType) * first));
    } else {
        c.glDrawArrays(c.GL_TRIANGLES, @intCast(c_int, first), @intCast(c_int, count));
    }
}
