const std = @import("std");

const asset = @import("./asset.zig");
const util = @import("./util.zig");
const Shader = @import("./Shader.zig");
const Texture = @import("./Texture.zig");
const RenderContext = @import("./RenderContext.zig");

const Self = @This();

transparent: bool = false,
shader: *Shader,
texture: *Texture,

pub fn init(am: *asset.Manager, path: []const u8) !Self {
    const transparent = std.mem.indexOf(u8, path, "glass") != null;

    var shader: *Shader = undefined;
    if (transparent) {
        shader = try am.load(Shader, "shaders/glass");
    } else {
        shader = try am.load(Shader, "shaders/main");
    }

    errdefer am.drop(shader);

    const texture = try am.load(Texture, path);

    return Self{
        .transparent = transparent,
        .shader = shader,
        .texture = texture,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    am.drop(self.shader);
    am.drop(self.texture);
}

pub fn bind(self: Self, ctx: *RenderContext) void {
    self.shader.bind();
    self.texture.bind();

    self.shader.uniformMatrix("u_world_to_camera", ctx.matrix_world_to_camera);
    self.shader.uniformMatrix("u_projection", ctx.matrix_projection);
}
