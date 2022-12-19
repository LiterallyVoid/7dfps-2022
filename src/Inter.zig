//! UI rendering

const std = @import("std");

const c = @import("./c.zig");
const linalg = @import("./linalg.zig");
const util = @import("./util.zig");
const asset = @import("./asset.zig");
const Shader = @import("./Shader.zig");
const Mesh = @import("./Mesh.zig");
const Font = @import("./Font.zig");
const Texture = @import("./Texture.zig");
const RenderContext = @import("./RenderContext.zig");

const Self = @This();

const Vertex = struct {
    position: [2]f32,
    uv: [2]f32,

    color: [4]u8,
};

const QuadList = @import("./quad_list.zig").QuadList(Vertex);

const Style = struct {
    font_size: f32 = 10.0,

    font: *Font,

    color: [4]u8 = .{ 255, 255, 255, 255 },
};

const Quad = struct {
    shader: Shader,
    texture: ?Texture,

    // x, y, w, h
    box: [4]f32,

    // same tbh
    uv_box: [4]f32,

    color: [4]u8,
};

const Full = struct {
    pub fn sizeForChild(self: *Full, vp: *Viewport) [2]?f32 {
        _ = self;
        return vp.size_hint;
    }

    pub fn done(self: *Full, vp: *Viewport) void {
        _ = self;
        _ = vp;
    }
};

const List = struct {
    pub const Options = struct {
        reverse: bool = false,
        justify: f32 = 0.0,

        fill_items: ?u32 = null,
    };

    primary_axis: u32,
    secondary_axis: u32,

    options: Options,

    pub fn sizeForChild(self: *List, vp: *Viewport) [2]?f32 {
        var size = vp.size_hint;
        size[self.primary_axis] = null;

        if (self.options.fill_items) |fill| {
            if (vp.size_hint[self.primary_axis] != null) {
                size[self.primary_axis] = vp.size_hint[self.primary_axis].? / @intToFloat(f32, fill);
            }
        }

        return size;
    }

    pub fn done(self: *List, vp: *Viewport) void {
        var accum: f32 = 0.0;

        var sign: f32 = if (self.options.reverse) -1.0 else 1.0;

        for (vp.children.items) |*child| {
            if (self.options.reverse) {
                accum += child.outer_size[self.primary_axis];
                child.offset[self.primary_axis] += vp.size_hint[self.primary_axis].?;
                child.offset[self.primary_axis] -= accum;
            } else {
                child.offset[self.primary_axis] += accum;
                accum += child.outer_size[self.primary_axis];
            }

            vp.outer_size[self.secondary_axis] = std.math.max(vp.outer_size[self.secondary_axis], child.outer_size[self.secondary_axis]);
        }

        const extra = sign * (vp.size_hint[self.primary_axis].? - accum) * self.options.justify;
        for (vp.children.items) |*child| {
            child.offset[self.primary_axis] += extra;
        }

        vp.outer_size[self.primary_axis] = vp.size_hint[self.primary_axis] orelse accum;
    }
};

const Anchor = struct {
    pub fn sizeForChild(self: *Anchor, vp: *Viewport) [2]?f32 {
        _ = self;
        _ = vp;

        return .{ null, null };
    }

    pub fn done(self: *Anchor, vp: *Viewport) void {
        _ = self;

        for (vp.children.items) |*child| {
            for (child.offset) |*offs, i| {
                if (vp.size_hint[i]) |sz_hint| {
                    offs.* += child.anchor_ratio[i] * sz_hint;
                }

                offs.* -= child.anchor_gravity[i] * child.outer_size[i];

                vp.outer_size[i] = std.math.max(vp.outer_size[i], child.outer_size[i] + child.offset[i]);
            }
        }
    }
};

pub const Viewport = struct {
    parent: ?*Viewport = null,
    inter: *Self,
    ready: bool = true,

    quads: std.ArrayListUnmanaged(Quad) = .{},
    children: std.ArrayListUnmanaged(Viewport) = .{},

    layout: union(enum) {
        full: Full,
        list: List,
        anchor: Anchor,
    } = .{ .full = .{} },

    offset: [2]f32 = .{ 0.0, 0.0 },
    quads_offset: [2]f32 = .{ 0.0, 0.0 },

    inner_offset: [2]f32 = .{ 0.0, 0.0 },
    inner_size: [2]f32 = .{ 0.0, 0.0 },

    outer_size: [2]f32 = .{ 0.0, 0.0 },
    size_hint: [2]?f32,

    clip: bool = false,

    style: Style,

    content_scale: f32 = 1.0,

    anchor_ratio: [2]f32 = .{ 0.0, 0.0 },
    anchor_gravity: [2]f32 = .{ 0.0, 0.0 },

    id: ?u32 = null,

    pub fn done(self: *Viewport) void {
        // self.quads.append(util.allocator, Quad {
        //     .shader = self.inter.flat_shader.*,
        //     .texture = null,
        //     .box = .{-self.quads_offset[0], -self.quads_offset[1], self.size_hint[0] orelse self.outer_size[0], self.size_hint[1] orelse self.outer_size[1]},
        //     .uv_box = .{ 0.0, 0.0, 0.0, 0.0 },
        //     .color = .{ 32, 0, 0, 32 },
        // }) catch unreachable;

        self.outer_size[0] /= self.content_scale;
        self.outer_size[1] /= self.content_scale;

        switch (self.layout) {
            inline else => |*l| l.done(self),
        }

        for (self.size_hint) |*elem| {
            if (elem.*) |*elem_nonnull| {
                elem_nonnull.* *= self.content_scale;
            }
        }

        if (self.parent) |parent| parent.childDone(self);
    }

    pub fn rows(self: *Viewport, options: List.Options) void {
        self.layout = .{ .list = .{ .primary_axis = 1, .secondary_axis = 0, .options = options } };
    }

    pub fn columns(self: *Viewport, options: List.Options) void {
        self.layout = .{ .list = .{ .primary_axis = 0, .secondary_axis = 1, .options = options } };
    }

    pub fn anchor(self: *Viewport) void {
        self.layout = .{ .anchor = .{} };
    }

    pub fn anchored(self: *Viewport, ratio: [2]f32, gravity: [2]f32) *Viewport {
        self.anchor_ratio = ratio;
        self.anchor_gravity = gravity;

        return self;
    }

    pub fn next(self: *Viewport) *Viewport {
        self.ready = false;

        const calculated_size = switch (self.layout) {
            inline else => |*l| l.sizeForChild(self),
        };

        self.children.append(util.allocator, .{
            .parent = self,
            .inter = self.inter,
            .size_hint = calculated_size,
            .style = self.style,
        }) catch {
            std.log.err("memory error in ui", .{});
            return self;
        };

        return &self.children.items[self.children.items.len - 1];
    }

    fn childDone(self: *Viewport, child: *Viewport) void {
        std.debug.assert(!self.ready); // out of order `done`
        self.ready = true;

        _ = child;
    }

    pub fn clip(self: *Viewport) *Viewport {
        self.clip = true;
        return self;
    }

    pub fn draw(self: *Viewport, outer_matrix: linalg.Mat4, size: [2]f32, mouse_c: [2]f32) void {
        var mouse = mouse_c;

        var matrix = outer_matrix;

        matrix = matrix.multiply(linalg.Mat4.translation(self.offset[0], self.offset[1], 0.0));
        mouse[0] -= self.offset[0];
        mouse[1] -= self.offset[1];

        if (self.id) |id| {
            if (mouse[0] > 0.0 and mouse[0] <= self.outer_size[0] and mouse[1] > 0.0 and mouse[1] <= self.outer_size[1]) {
                self.inter.hover = id;
                self.inter.hover_mouse = .{
                    mouse[0] / self.outer_size[0],
                    mouse[1] / self.outer_size[1],
                };
            }
        }

        if (self.content_scale != 1.0) {
            matrix = matrix.multiply(linalg.Mat4.scale(self.content_scale));
            mouse[0] /= self.content_scale;
            mouse[1] /= self.content_scale;
        }

        var quad_i: usize = self.quads.items.len;
        while (quad_i > 0) {
            quad_i -= 1;

            const quad = self.quads.items[quad_i];

            var vertices: [4]Vertex = undefined;

            for (vertices) |*vertex, i| {
                var x = @intToFloat(f32, i / 2);
                var y = @intToFloat(f32, i % 2);

                var pos_x = self.quads_offset[0] + quad.box[0] + quad.box[2] * x;
                var pos_y = self.quads_offset[1] + quad.box[1] + quad.box[3] * y;

                var position_vec4 = linalg.Vec4.new(pos_x, pos_y, 0.0, 1.0);
                position_vec4 = matrix.multiplyVector(position_vec4);
                vertex.position = position_vec4.data[0..2].*;

                vertex.uv = .{
                    quad.uv_box[0] + quad.uv_box[2] * x,
                    quad.uv_box[1] + quad.uv_box[3] * y,
                };

                vertex.color = quad.color;
            }

            self.inter.setShader(quad.shader);
            self.inter.setTexture(quad.texture);
            self.inter.quad_list.addQuad(vertices);

            if (quad_i == 0) break;
        }

        for (self.children.items) |*child| {
            child.draw(matrix, size, mouse);
        }

        self.quads.deinit(util.allocator);
        self.children.deinit(util.allocator);
    }

    pub fn contentScale(self: *Viewport, content_scale: f32) *Viewport {
        self.content_scale *= content_scale;

        for (self.size_hint) |*elem| {
            if (elem.*) |*elem_nonnull| {
                elem_nonnull.* /= content_scale;
            }
        }

        return self;
    }

    pub fn fontSize(self: *Viewport, font_size: f32) *Viewport {
        self.style.font_size = font_size;
        return self;
    }

    pub fn font(self: *Viewport, text_font: *Font) *Viewport {
        self.style.font = text_font;
        return self;
    }

    pub fn image(self: *Viewport, texture: Texture, size: [2]f32) *Viewport {
        self.quads.append(util.allocator, Quad {
            .shader = self.inter.texture_shader.*,
            .texture = texture,
            .box = .{ 0.0, 0.0, size[0], size[1] },
            .uv_box = .{ 0.0, 0.0, 1.0, 1.0 },
            .color = self.style.color,
        }) catch return self;

        self.inner_size = size;
        self.outer_size = size;

        return self;
    }

    pub fn text(self: *Viewport, txt: []const u8) *Viewport {
        var width: f32 = 0.0;
        var height: f32 = 0.0;

        const glyphs = self.style.font.layout(txt, &width, &height) catch return self;
        defer util.allocator.free(glyphs);

        width *= self.style.font_size;
        height *= self.style.font_size;

        const texture = self.style.font.texture();

        for (glyphs) |glyph| {
            var box = glyph.box;

            for (box) |*el| {
                el.* *= self.style.font_size;
            }

            self.quads.append(util.allocator, Quad {
                .shader = self.inter.text_shader.*,
                .texture = texture,
                .box = box,
                .uv_box = glyph.uv_box,
                .color = self.style.color,
            }) catch return self;
        }

        self.inner_size = .{ width, height };
        self.outer_size = .{ width, height };

        return self;
    }

    pub fn color(self: *Viewport, color_: [4]u8) *Viewport {
        self.style.color = color_;
        return self;
    }

    pub fn pad(self: *Viewport, padding: [2]f32) *Viewport {
        for (padding) |el, i| {
            self.inner_offset[i] -= el;
            self.quads_offset[i] += el;

            self.inner_size[i] += el * 2.0;
            self.outer_size[i] += el * 2.0;
        }

        return self;
    }

    pub fn center(self: *Viewport, margin: [2]f32) *Viewport {
        return self.fill(margin, .{ 0.5, 0.5 });
    }

    pub fn fill(self: *Viewport, margin: [2]f32, gravity: [2]f32) *Viewport {
        var i: usize = 0;

        while (i < 2) : (i += 1) {
            if (self.size_hint[i]) |size_hint| {
                const room = (size_hint - self.inner_size[i]);
                const room_without_margin = room - margin[i] * 2.0;

                self.quads_offset[i] += margin[i];

                self.quads_offset[i] += room_without_margin * gravity[0];
                self.inner_offset[i] -= room_without_margin * gravity[0];

                self.inner_size[i] += room_without_margin;
                self.outer_size[i] += room;
            } else {
                self.quads_offset[i] += margin[i];
                self.outer_size[i] += margin[i] * 2;
            }
        }

        return self;
    }

    const Background = struct {
        color: [4]u8 = .{ 255, 255, 255, 255 },
    };

    pub fn background(self: *Viewport, bg: Background) *Viewport {
        self.quads.append(util.allocator, Quad {
            .shader = self.inter.flat_shader.*,
            .texture = null,
            .box = .{ self.inner_offset[0], self.inner_offset[1], self.inner_size[0], self.inner_size[1] },
            .uv_box = undefined,
            .color = bg.color,
        }) catch return self;

        return self;
    }

    pub fn sliderRect(self: *Viewport, start: f32, end: f32) *Viewport {
        self.quads.append(util.allocator, Quad {
            .shader = self.inter.flat_shader.*,
            .texture = null,
            .box = .{ self.inner_offset[0] + self.inner_size[0] * start, self.inner_offset[1], self.inner_size[0] * (end - start), self.inner_size[1] },
            .uv_box = undefined,
            .color = self.style.color,
        }) catch return self;

        return self;
    }
};

hover: ?u32,
hover_mouse: [2]f32,

text_shader: *Shader,
flat_shader: *Shader,
texture_shader: *Shader,
default_font: *Font,

quad_list: QuadList,
current_shader: Shader,

pub fn init(self: *Self, am: *asset.Manager) !void {
    self.text_shader = try am.load(Shader, "shaders/text");
    self.flat_shader = try am.load(Shader, "shaders/ui-flat");
    self.texture_shader = try am.load(Shader, "shaders/ui-texture");
    self.default_font = try am.load(Font, "fonts/font.ttf");

    self.quad_list = QuadList.init();
    self.current_shader = undefined;
}

pub fn deinit(self: *Self, am: *asset.Manager) void {
    am.drop(self.flat_shader);
    am.drop(self.text_shader);
    am.drop(self.texture_shader);
    am.drop(self.default_font);

    self.quad_list.deinit();
}

pub fn begin(self: *Self, size: [2]f32) Viewport {
    return Viewport{
        .inter = self,
        .size_hint = .{ size[0], size[1] },
        .style = .{
            .font = self.default_font,
        },
    };
}

fn setShader(self: *Self, shader: Shader) void {
    if (self.current_shader.gl_program == shader.gl_program) return;

    self.quad_list.flush();
    shader.bindRaw();
    self.current_shader = shader;
}

fn setTexture(self: *Self, texture_opt: ?Texture) void {
    defer self.quad_list.texture = texture_opt;

    const current_texture = self.quad_list.texture orelse {
        self.quad_list.flush();
        return;
    };

    const texture = texture_opt orelse {
        self.quad_list.flush();
        return;
    };

    if (!current_texture.eql(texture)) {
        self.quad_list.flush();
    }
}

pub fn flush(self: *Self, viewport: *Viewport, mouse: [2]f32) void {
    self.hover = null;
    self.current_shader = self.text_shader.*;
    self.current_shader.bindRaw();

    c.glDisable(c.GL_DEPTH_TEST);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);

    const size = .{ viewport.size_hint[0].?, viewport.size_hint[1].? };
    var matrix = linalg.Mat4.orthographic(0.0, size[0], 0.0, size[1], -1.0, 1.0);

    viewport.draw(matrix, size, mouse);

    self.quad_list.flush();

    c.glEnable(c.GL_DEPTH_TEST);
    c.glDisable(c.GL_BLEND);
}
