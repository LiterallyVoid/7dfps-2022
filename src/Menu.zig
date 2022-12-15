const std = @import("std");

const asset = @import("./asset.zig");
const c = @import("./c.zig");
const util = @import("./util.zig");
const linalg = @import("./linalg.zig");

const Shader = @import("./Shader.zig");
const Mesh = @import("./Mesh.zig");
const Map = @import("./Map.zig");
const PhysicsMesh = @import("./PhysicsMesh.zig");
const RenderContext = @import("./RenderContext.zig");
const Game = @import("./Game.zig");
const Inter = @import("./Inter.zig");

const Self = @This();

visible: bool,

pub fn init(self: *Self, am: *asset.Manager) !void {
    _ = am;

    self.* = .{
        .visible = true,
    };
}

pub fn deinit(self: *Self, am: *asset.Manager) void {
    _ = self;
    _ = am;
}

pub fn handleEsc(self: *Self) void {
    if (self.visible) {
        self.visible = false;
    } else {
        self.visible = true;
    }
}

pub fn drawUI(self: *Self, into: *Inter.Viewport) void {
    if (!self.visible) return;

    {
        const bg = into.next();
        defer bg.done();

        _ = bg.center(.{ 0.0, 0.0 }).background(.{ .color = .{ 0, 0, 0, 64 } });
    }

    {
        const menu = into.next();
        defer menu.done();

        menu.rows(.{});

        menu.next().fontSize(60.0).text("PLAY").pad(.{10.0, 10.0}).center(.{20.0, 5.0}).background(.{.color = .{ 255, 64, 255, 255 }}).done();
        menu.next().fontSize(30.0).text("CONTROLS").pad(.{5.0, 5.0}).center(.{20.0, 5.0}).background(.{.color = .{ 96, 32, 96, 255 }}).done();
    }
}
