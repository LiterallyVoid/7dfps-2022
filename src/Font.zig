const std = @import("std");

const asset = @import("./asset.zig");
const c = @import("./c.zig");
const util = @import("./util.zig");
const Texture = @import("./Texture.zig");

const Self = @This();

const GlyphBox = struct {
    box: [4]f32,
    uv_box: [4]f32,
};

const SDF_SCALE = 64.0;
const ATLAS_SIZE = 1024;
const FONT_ASCENT_FUDGE = 0.8;

font: c.stbtt_fontinfo,
ttf_data: []const u8,

scale: f32 = 0.0,

gl_texture: c.GLuint,

loaded_glyphs: std.AutoHashMap(c_int, GlyphBox),

// VERY simple packing algorithm!
pack_x: usize = 0,
pack_y: usize = 0,
pack_h: usize = 0,

pub fn init(am: *asset.Manager, path: []const u8) !Self {
    const file = try am.openPath(path);
    defer file.close();

    const data = try file.reader().readAllAlloc(util.allocator, 16 * 1024 * 1024);
    errdefer util.allocator.free(data);

    var font: c.stbtt_fontinfo = undefined;

    if (c.stbtt_InitFont(&font, data.ptr, 0) == 0) {
        return error.FontLoadFailed;
    }

    var gl_texture: c.GLuint = undefined;

    c.glGenTextures(1, &gl_texture);
    c.glBindTexture(c.GL_TEXTURE_2D, gl_texture);

    var zeroes = util.allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE) catch unreachable;
    defer util.allocator.free(zeroes);
    for (zeroes) |*zero| { zero.* = 0; }

    c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RED, ATLAS_SIZE, ATLAS_SIZE, 0, c.GL_RED, c.GL_UNSIGNED_BYTE, zeroes.ptr);

    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);

    var ascent: c_int = 0;
    c.stbtt_GetFontVMetrics(&font, &ascent, null, null);

    var scale = c.stbtt_ScaleForPixelHeight(&font, SDF_SCALE);
    const ascent_px = @intToFloat(f32, ascent) * scale * FONT_ASCENT_FUDGE;

    scale *= (SDF_SCALE / ascent_px);

    return Self {
        .ttf_data = data,
        .font = font,
        .scale = scale,
        .gl_texture = gl_texture,
        .loaded_glyphs = std.AutoHashMap(c_int, GlyphBox).init(util.allocator),
    };
}

pub fn deinit(self: *Self, am: *asset.Manager) void {
    c.glDeleteTextures(1, &self.gl_texture);

    self.loaded_glyphs.deinit();

    _ = am;

    util.allocator.free(self.ttf_data);
}

fn packUv(self: *Self, pixels: [*]u8, width: usize, height: usize) [4]f32 {
    const padding = 4;
    var padded_width = width + padding * 2;
    var padded_height = height + padding * 2;

    if (self.pack_x + padded_width > ATLAS_SIZE) {
        self.pack_y += self.pack_h;
        self.pack_x = 0;
    }

    var x: usize = self.pack_x + padding;
    var y: usize = self.pack_y + padding;

    self.pack_x += padded_width;
    self.pack_h = std.math.max(self.pack_h, padded_height);

    if (self.pack_y + padded_height > ATLAS_SIZE) {
        std.log.err("no room for glyph!", .{});
        return .{ 0.0, 0.0, 0.0, 0.0 };
    }

    c.glBindTexture(c.GL_TEXTURE_2D, self.gl_texture);

    c.glTexSubImage2D(c.GL_TEXTURE_2D, 0, @intCast(c_int, x), @intCast(c_int, y), @intCast(c_int, width), @intCast(c_int, height), c.GL_RED, c.GL_UNSIGNED_BYTE, pixels);

    return .{
        (@intToFloat(f32, x)) / @intToFloat(f32, ATLAS_SIZE),
        (@intToFloat(f32, y)) / @intToFloat(f32, ATLAS_SIZE),
        (@intToFloat(f32, width)) / @intToFloat(f32, ATLAS_SIZE),
        (@intToFloat(f32, height)) / @intToFloat(f32, ATLAS_SIZE),
    };
}

pub fn glyphBox(self: *Self, glyph: c_int) GlyphBox {
    if (self.loaded_glyphs.get(glyph)) |box| return box;

    var x: c_int = 0;
    var y: c_int = 0;
    var width: c_int = 0;
    var height: c_int = 0;

    const pixels = c.stbtt_GetGlyphSDF(&self.font, self.scale, glyph, 11, 127, 10.0, &width, &height, &x, &y) orelse {
        const box = GlyphBox {
            .box = .{ 0.0, 0.0, 0.0, 0.0 },
            .uv_box = .{ 0.0, 0.0, 0.0, 0.0 },
        };

        self.loaded_glyphs.put(glyph, box) catch {};
        return box;
    };

    defer c.stbtt_FreeSDF(pixels, null);

    var box = GlyphBox {
        .box = .{
            @intToFloat(f32, x) / SDF_SCALE,
            @intToFloat(f32, y) / SDF_SCALE,
            @intToFloat(f32, width) / SDF_SCALE,
            @intToFloat(f32, height) / SDF_SCALE,
        },

        .uv_box = self.packUv(pixels, @intCast(usize, width), @intCast(usize, height)),
    };

    box.box[1] += 1.0;

    self.loaded_glyphs.put(glyph, box) catch {};

    return box;
}

pub fn layout(self: *Self, text: []const u8, width: *f32, height: *f32) ![]GlyphBox {
    var list = std.ArrayList(GlyphBox).init(util.allocator);
    errdefer list.deinit();

    var x: f32 = 0.0;
    var y: f32 = 0.0;

    for (text) |ch| {
        const glyph = c.stbtt_FindGlyphIndex(&self.font, ch);

        var box = self.glyphBox(glyph);

        box.box[0] += x;
        box.box[1] += y;

        var advance: c_int = 0;
        var bearing: c_int = 0;

        c.stbtt_GetCodepointHMetrics(&self.font, ch, &advance, &bearing);

        x += (@intToFloat(f32, advance) * self.scale) / SDF_SCALE;

        try list.append(box);
    }

    width.* = x;
    height.* = y + 1.0;

    return list.toOwnedSlice();
}

pub fn texture(self: *Self) Texture {
    // SUPER HACKY!
    return Texture {
        .gl_texture = self.gl_texture,
    };
}
