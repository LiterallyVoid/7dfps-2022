const std = @import("std");

const asset = @import("./asset.zig");
const c = @import("./c.zig");
const util = @import("./util.zig");
const linalg = @import("./linalg.zig");

const App = @import("./App.zig");

comptime {
    _ = @import("./PhysicsMesh.zig");
}

pub fn main() !void {
    defer _ = util.gpa.deinit();

    if (c.glfwInit() == 0) return error.GLFWInitFailed;
    defer c.glfwTerminate();

    var app: App = undefined;
    try app.init();
    defer app.deinit();

    app.run();
}
