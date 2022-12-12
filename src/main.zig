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

    c.glfwMakeContextCurrent(window);
    if (c.gladLoadGL(c.glfwGetProcAddress) == 0) return error.OpenGLLoadFailed;

    var am = asset.Manager{
        .prefix = "data",
    };

    const map = try am.load(Map, "maps/sandbox.map");
    defer am.drop(map);

    const mesh = Mesh.init(.{ .static = true, .indexed = true }, ImVertex);
    defer mesh.deinit();

    mesh.upload(ImVertex, &.{
        .{
            .position = .{ -0.5, -0.5 },
            .uv = .{ 0.0, 0.0 },
        },
        .{
            .position = .{ 0.5, -0.5 },
            .uv = .{ 1.0, 0.0 },
        },
        .{
            .position = .{ 0.5, 0.5 },
            .uv = .{ 1.0, 1.0 },
        },
        .{
            .position = .{ -0.5, 0.5 },
            .uv = .{ -1.0, 1.0 },
        },
    });

    mesh.uploadIndices(&.{
        0,
        1,
        2,
        2,
        3,
        0,
    });

    c.glEnable(c.GL_DEPTH_TEST);

    var pitch: f32 = 0.0;
    var yaw: f32 = 0.0;

    var mouse: [2]f64 = undefined;

    if (c.glfwRawMouseMotionSupported() != 0) {
        c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
    }

    c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);

    var position = linalg.Vec3.new(0.0, 0.0, 1.0);
    var velocity = linalg.Vec3.new(0.0, 0.0, 0.0);

    var time: f64 = c.glfwGetTime();

    while (c.glfwWindowShouldClose(window) == 0) {
        var size: [2]c_int = undefined;
        c.glfwGetFramebufferSize(window, &size[0], &size[1]);

        c.glViewport(0, 0, size[0], size[1]);

        c.glClearColor(0.2, 0.3, 0.6, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

        var delta = blk: {
            const new_time = c.glfwGetTime();

            var delta_ = new_time - time;

            time = new_time;

            break :blk @floatCast(f32, delta_);
        };

        {
            var new_mouse: [2]f64 = undefined;
            c.glfwGetCursorPos(window, &new_mouse[0], &new_mouse[1]);

            yaw -= @floatCast(f32, new_mouse[0] - mouse[0]) * 0.022 * 0.1;
            pitch -= @floatCast(f32, new_mouse[1] - mouse[1]) * 0.022 * 0.1;

            mouse = new_mouse;
        }

        var aspect = @intToFloat(f32, size[0]) / @intToFloat(f32, size[1]);

        const half_extents = linalg.Vec3.new(0.5, 0.5, 0.5);

        const margin = 0.0001;
        if (map.phys_mesh.nudge(position, half_extents.add(linalg.Vec3.new(margin, margin, margin)))) |impact| {
            position = position.add(impact.offset);
            velocity = velocity.sub(impact.plane.xyz().mulScalar(velocity.dot(impact.plane.xyz())));
        }

        {
            var i: usize = 0;
            var remaining: f32 = 1.0;

            while (i < 4) : (i += 1) {
                var offset = velocity.mulScalar(delta * remaining);

                var impact = map.phys_mesh.traceLine(position, half_extents, offset) orelse {
                    position = position.add(offset);
                    break;
                };

                position = position.add(offset.mulScalar(impact.time));

                velocity = velocity.sub(impact.plane.xyz().mulScalar(velocity.dot(impact.plane.xyz())));
                remaining *= 1.0 - impact.time;
            }
        }
        velocity = velocity.mulScalar(std.math.pow(f32, 0.5, delta * 10.0));

        var camera =
            linalg.Mat4.translation(position.data[0], position.data[1], position.data[2])
            .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), yaw))
            .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 1.0, 0.0), pitch))
            .multiply(linalg.Mat4.rotation(linalg.Vec3.new(0.0, 0.0, 1.0), std.math.pi * 0.5));

        var forward = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(0.0, 0.0, -1.0));
        var right = camera.toMat3().multiplyVectorOpp(linalg.Vec3.new(1.0, 0.0, 0.0));

        const speed = 40.0;

        if (c.glfwGetKey(window, c.GLFW_KEY_E) == c.GLFW_PRESS) {
            velocity = velocity.add(forward.mulScalar(delta * speed));
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
            velocity = velocity.add(forward.mulScalar(delta * -speed));
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
            velocity = velocity.add(right.mulScalar(delta * -speed));
        }

        if (c.glfwGetKey(window, c.GLFW_KEY_F) == c.GLFW_PRESS) {
            velocity = velocity.add(right.mulScalar(delta * speed));
        }

        var ctx = RenderContext {
            .matrix_projection = linalg.Mat4.perspective(1.5, aspect, 0.1, 100.0),
            .matrix_camera_to_world = camera,
            .matrix_world_to_camera = camera.inverse(),
        };

        map.draw(&ctx);

        c.glEnable(c.GL_CULL_FACE);
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);
        map.drawTransparent(&ctx);
        c.glDisable(c.GL_BLEND);

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
