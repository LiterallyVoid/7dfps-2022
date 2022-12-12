const std = @import("std");

const c = @import("./c.zig");

const asset = @import("./asset.zig");
const util = @import("./util.zig");
const linalg = @import("./linalg.zig");
const Shader = @import("./Shader.zig");
const Mesh = @import("./Mesh.zig");
const Map = @import("./Map.zig");
const PhysicsMesh = @import("./PhysicsMesh.zig");
const RenderContext = @import("./RenderContext.zig");
const Game = @import("./Game.zig");

comptime {
    _ = PhysicsMesh;
}

const ImVertex = struct {
    position: [2]f32,
    uv: [2]f32,
};

pub fn main() !void {
    defer _ = util.gpa.deinit();

    if (c.glfwInit() == 0) return error.GLFWInitFailed;
    defer c.glfwTerminate();

    const window = c.glfwCreateWindow(640, 480, "7dfps 2022", null, null) orelse return error.GLFWWindowFailed;
    defer c.glfwDestroyWindow(window);

    c.glfwSetWindowPos(window, 0, 1080 - 480);

    c.glfwMakeContextCurrent(window);
    if (c.gladLoadGL(c.glfwGetProcAddress) == 0) return error.OpenGLLoadFailed;

    var am = asset.Manager{
        .prefix = "data",
    };

    var game: Game = undefined;
    try game.init(&am, "maps/sandbox.map");
    defer game.deinit(&am);

    const map = try am.load(Map, "maps/sandbox.map");
    defer am.drop(map);

    c.glEnable(c.GL_DEPTH_TEST);

    var pitch: f32 = 0.0;
    var yaw: f32 = 0.0;

    var mouse: [2]f64 = undefined;

    var locked: bool = false;

    if (c.glfwRawMouseMotionSupported() != 0) {
        c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
    }

    var time: f64 = c.glfwGetTime();

    while (c.glfwWindowShouldClose(window) == 0) {
        var size: [2]c_int = undefined;
        c.glfwGetFramebufferSize(window, &size[0], &size[1]);

        c.glViewport(0, 0, size[0], size[1]);

        c.glClearColor(0.2, 0.3, 0.6, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        if (c.glfwGetMouseButton(window, c.GLFW_MOUSE_BUTTON_LEFT) == c.GLFW_PRESS) {
            c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
            locked = true;
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_ESCAPE) == c.GLFW_PRESS) {
            c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
            locked = false;
        }

        var delta = blk: {
            const new_time = c.glfwGetTime();

            var delta_ = new_time - time;

            time = new_time;

            break :blk @floatCast(f32, delta_);
        };

        {
            var new_mouse: [2]f64 = undefined;
            c.glfwGetCursorPos(window, &new_mouse[0], &new_mouse[1]);

            if (locked) {
                yaw -= @floatCast(f32, new_mouse[0] - mouse[0]) * 0.022 * 0.1;
                pitch -= @floatCast(f32, new_mouse[1] - mouse[1]) * 0.022 * 0.1;
            }

            mouse = new_mouse;
        }

        var input = Game.Input {};
        input.angle = .{ pitch, yaw };

        if (c.glfwGetKey(window, c.GLFW_KEY_E) == c.GLFW_PRESS) {
            input.movement[1] += 1.0;
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
            input.movement[1] -= 1.0;
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
            input.movement[0] -= 1.0;
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_F) == c.GLFW_PRESS) {
            input.movement[0] += 1.0;
        }

        input.keys[0] = c.glfwGetKey(window, c.GLFW_KEY_SPACE) == c.GLFW_PRESS;

        var aspect = @intToFloat(f32, size[0]) / @intToFloat(f32, size[1]);

        var ctx: RenderContext = undefined;
        ctx.aspect = aspect;

        game.input(input);

        game.update(delta);

        game.draw(&ctx);

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
