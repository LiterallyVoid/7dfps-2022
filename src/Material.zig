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

    pub fn serialize(self: LoadInfo) []u8 {
        return std.fmt.allocPrint(util.allocator, "{s}/{}", .{ self.path, self.options.skeletal }) catch unreachable;
    }
};

pub const Options = struct {
    skeletal: bool = false,
};

options: Options,

transparent: bool = false,
shader: *Shader,
texture: *Texture,
normal_texture: ?*Texture,
reflection_texture: *Texture,

pub fn serializeInfo(info: LoadInfo) []u8 {
    return info.serialize();
}

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

    const normalmap_path = try std.mem.concat(
        util.allocator,
        u8,
        &.{
            texture_path[0..texture_path.len - 4],
            "-normal.png",
        },
    );
    defer util.allocator.free(normalmap_path);

    const texture = try am.load(Texture, texture_path);
    const normalmap = am.load(Texture, normalmap_path)
        catch try am.load(Texture, "textures/grid-normal0001.png");
    const reflect = try am.load(Texture, "textures/reflect.png");

    return Self{
        .options = info.options,
        .shader = shader,
        .texture = texture,
        .normal_texture = normalmap,
        .reflection_texture = reflect,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    am.drop(self.shader);
    am.drop(self.texture);
    if (self.normal_texture) |tex| am.drop(tex);
    am.drop(self.reflection_texture);
}

pub fn bind(self: Self, ctx: *RenderContext) void {
    self.shader.bind(ctx);
    self.shader.uniformTexture("u_reflect", 1, self.reflection_texture.*);
    if (self.normal_texture) |tex| self.shader.uniformTexture("u_normalmap", 2, tex.*);
    self.shader.uniformTexture("u_texture", 0, self.texture.*);
}
