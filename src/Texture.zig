const std = @import("std");

const c = @import("./c.zig");

const asset = @import("./asset.zig");
const util = @import("./util.zig");
const Shader = @import("./Shader.zig");

const Self = @This();

gl_texture: c.GLuint,

pub fn init(am: *asset.Manager, path: []const u8) !Self {
    var file = try am.openPath(path);
    defer file.close();

    var contents = try file.reader().readAllAlloc(util.allocator, 16 * 1024 * 1024);
    defer util.allocator.free(contents);

    var width: c_int = 0;
    var height: c_int = 0;

    c.stbi_set_flip_vertically_on_load(1);

    var pixels = c.stbi_load_from_memory(contents.ptr, @intCast(c_int, contents.len), &width, &height, null, 4) orelse return error.ImageLoadFailed;
    defer c.stbi_image_free(pixels);

    var gl_texture: c.GLuint = undefined;

    c.glGenTextures(1, &gl_texture);
    c.glBindTexture(c.GL_TEXTURE_2D, gl_texture);

    c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels);
    c.glGenerateMipmap(c.GL_TEXTURE_2D);

    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);

    return Self{
        .gl_texture = gl_texture,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    _ = am;

    c.glDeleteTextures(1, &self.gl_texture);
}

pub fn bind(self: Self, slot: u32) void {
    c.glActiveTexture(@intCast(c_uint, c.GL_TEXTURE0) + slot);
    c.glBindTexture(c.GL_TEXTURE_2D, self.gl_texture);
}
