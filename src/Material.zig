const std = @import("std");

const asset = @import("./asset.zig");
const util = @import("./util.zig");
const Shader = @import("./Shader.zig");
const Texture = @import("./Texture.zig");
const RenderContext = @import("./RenderContext.zig");

const Self = @This();

pub const LoadInfo = struct {
    path: []const u8,
    options: Options = .{},
};

pub const Options = struct {
    skeletal: bool = false,
};

options: Options,

transparent: bool = false,
shader: *Shader,
texture: *Texture,

pub fn init(am: *asset.Manager, info: LoadInfo) !Self {
    var shader: *Shader = undefined;

    var texture_path = info.path;

    if (std.mem.indexOf(u8, info.path, "!")) |exclaim| {
        shader = try am.load(Shader, info.path[0..exclaim]);
        texture_path = info.path[exclaim + 1 ..];
    } else {
        if (info.options.skeletal) {
            shader = try am.load(Shader, "shaders/skeletal");
        } else {
            shader = try am.load(Shader, "shaders/main");
        }
    }

    errdefer am.drop(shader);

    const texture = try am.load(Texture, texture_path);

    return Self{
        .options = info.options,
        .shader = shader,
        .texture = texture,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    am.drop(self.shader);
    am.drop(self.texture);
}

pub fn bind(self: Self, ctx: *RenderContext) void {
    self.shader.bind(ctx);
    self.shader.uniformTexture("u_texture", 0, self.texture);
}
