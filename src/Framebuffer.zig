const std = @import("std");

const c = @import("./c.zig");

const Self = @This();

gl_fbo: c.GLuint,
gl_tex_colors: [8]?c.GLuint = .{ null } ** 8,
gl_tex_depth: ?c.GLuint = null,

color_fmts: []const c.GLint,

old_size: [2]usize = .{ 0, 0 },
size: [2]usize = .{ 0, 0 },

depth: bool = false,

levels: usize = 1,

pub fn init(color_fmts: []const c.GLint, depth: bool) Self {
    var fbo: c.GLuint = undefined;

    c.glGenFramebuffers(1, &fbo);

    var all_buffers = [_]c.GLuint {
        c.GL_COLOR_ATTACHMENT0,
        c.GL_COLOR_ATTACHMENT1,
        c.GL_COLOR_ATTACHMENT2,
        c.GL_COLOR_ATTACHMENT3,
        c.GL_COLOR_ATTACHMENT4,
        c.GL_COLOR_ATTACHMENT5,
        c.GL_COLOR_ATTACHMENT6,
        c.GL_COLOR_ATTACHMENT7,
    };

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, fbo);

    c.glDrawBuffers(@intCast(c_int, color_fmts.len), &all_buffers);

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);

    return Self {
        .gl_fbo = fbo,
        .color_fmts = color_fmts,
        .depth = depth,
    };
}

pub fn deinit(self: *Self) void {
    c.glDeleteFramebuffers(1, &self.gl_fbo);

    for (self.gl_tex_colors) |tex| {
        if (tex) |*always_tex| {
            c.glDeleteTextures(1, always_tex);
        }
    }

    if (self.gl_tex_depth) |*tex| {
        c.glDeleteTextures(1, tex);
    }
}

pub fn resize(self: *Self, size: [2]usize) void {
    self.size = size;

    if (size[0] == 0 and size[1] == 0) {
        for (self.gl_tex_colors) |*tc| {
            if (tc.*) |*tex| {
                c.glDeleteTextures(1, tex);
            }

            tc.* = null;
        }

        if (self.gl_tex_depth) |*depth| {
            c.glDeleteTextures(1, depth);
            self.gl_tex_depth = null;
        }
    }
}

fn genTextures(self: *Self) void {
    for (self.color_fmts) |color_fmt, i| {
        if (self.gl_tex_colors[i]) |*col| {
            c.glDeleteTextures(1, col);
        }

        var color: c.GLuint = undefined;

        c.glGenTextures(1, &color);
        c.glBindTexture(c.GL_TEXTURE_2D, color);

        c.glTexImage2D(c.GL_TEXTURE_2D, 0, color_fmt, @intCast(c_int, self.size[0]), @intCast(c_int, self.size[1]), 0, c.GL_RED, c.GL_UNSIGNED_BYTE, null);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP);

        c.glFramebufferTexture(c.GL_FRAMEBUFFER, @intCast(c_uint, c.GL_COLOR_ATTACHMENT0) + @intCast(c_uint, i), color, 0);

        self.gl_tex_colors[i] = color;
    }

    if (self.depth) {
        var depth: c.GLuint = undefined;
        c.glGenTextures(1, &depth);
        c.glBindTexture(c.GL_TEXTURE_2D, depth);

        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_DEPTH_COMPONENT24, @intCast(c_int, self.size[0]), @intCast(c_int, self.size[1]), 0, c.GL_DEPTH_COMPONENT, c.GL_UNSIGNED_INT, null);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_COMPARE_MODE, c.GL_COMPARE_REF_TO_TEXTURE);

        c.glFramebufferTexture(c.GL_FRAMEBUFFER, c.GL_DEPTH_ATTACHMENT, depth, 0);

        self.gl_tex_depth = depth;
    }
}

pub fn bind(self: *Self) void {
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.gl_fbo);

    if (!std.meta.eql(self.size, self.old_size)) {
        if (self.gl_tex_depth) |*tex| {
            c.glDeleteTextures(1, tex);
        }

        self.old_size = self.size;
        self.genTextures();
    }

    c.glViewport(0, 0, @intCast(c_int, self.size[0]), @intCast(c_int, self.size[1]));
}
