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

const Self = @This();

const Button = union(enum) {
    mouse_button: c_int,
    key: c_int,
};

const Binding = struct {
    action_name: []const u8,

    press_ptr: ?*bool = null,
    hold_ptr: ?*bool = null,

    callback: ?*const fn (app: *Self, data: ?*anyopaque) void = null,
    callback_data: ?*anyopaque = null,
};

window: *c.GLFWwindow,
asset_manager: asset.Manager,

time: f64,
last_mouse_position: [2]f64,

bindings: std.AutoHashMap(Button, Binding),

movement_keys: [4]bool,

game: Game,
game_input: Game.Input,

pub fn init(self: *Self) !void {
    self.window = c.glfwCreateWindow(640, 480, "7dfps 2022", null, null) orelse return error.GLFWWindowFailed;
    errdefer c.glfwDestroyWindow(self.window);

    c.glfwMakeContextCurrent(self.window);
    if (c.gladLoadGL(c.glfwGetProcAddress) == 0) return error.OpenGLLoadFailed;

    self.asset_manager = asset.Manager{
        .prefix = "data",
    };
    //errdefer self.asset_manager.deinit();

    try self.game.init(&self.asset_manager, "maps/sandbox.map");

    if (c.glfwRawMouseMotionSupported() != 0) {
        c.glfwSetInputMode(self.window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
    }

    c.glEnable(c.GL_DEPTH_TEST);

    self.time = c.glfwGetTime();

    self.bindings = std.AutoHashMap(Button, Binding).init(util.allocator);

    try self.bindings.put(.{ .key = c.GLFW_KEY_E }, .{
        .action_name = "game/forward",

        .hold_ptr = &self.movement_keys[0],
    });

    try self.bindings.put(.{ .key = c.GLFW_KEY_D }, .{
        .action_name = "game/back",

        .hold_ptr = &self.movement_keys[1],
    });

    try self.bindings.put(.{ .key = c.GLFW_KEY_S }, .{
        .action_name = "game/left",

        .hold_ptr = &self.movement_keys[2],
    });

    try self.bindings.put(.{ .key = c.GLFW_KEY_F }, .{
        .action_name = "game/right",

        .hold_ptr = &self.movement_keys[3],
    });

    try self.bindings.put(.{ .key = c.GLFW_KEY_SPACE }, .{
        .action_name = "game/jump",

        .press_ptr = &self.game_input.keys_pressed[0],
        .hold_ptr = &self.game_input.keys_held[0],
    });

    try self.bindings.put(.{ .mouse_button = c.GLFW_MOUSE_BUTTON_LEFT }, .{
        .action_name = "game/attack",

        .press_ptr = &self.game_input.keys_pressed[1],
        .hold_ptr = &self.game_input.keys_held[1],
    });

    try self.bindings.put(.{ .key = c.GLFW_KEY_R }, .{
        .action_name = "game/reload",

        .press_ptr = &self.game_input.keys_pressed[2],
        .hold_ptr = &self.game_input.keys_held[2],
    });

    c.glfwSetWindowUserPointer(self.window, self);

    _ = c.glfwSetCursorPosCallback(self.window, cursorCallback);
    _ = c.glfwSetMouseButtonCallback(self.window, mouseButtonCallback);
    _ = c.glfwSetKeyCallback(self.window, keyCallback);
}

pub fn deinit(self: *Self) void {
    c.glfwDestroyWindow(self.window);
    self.bindings.deinit();
    self.game.deinit();
}

pub fn run(self: *Self) void {
    while (c.glfwWindowShouldClose(self.window) == 0) {
        self.tick();
    }
}

fn bindingSet(self: *Self, button: Button, held: bool) void {
    const binding_entry = self.bindings.getEntry(button) orelse return;
    const binding = binding_entry.value_ptr;

    if (held) {
        if (binding.press_ptr) |press_ptr| {
            press_ptr.* = true;
        }
    }

    if (binding.hold_ptr) |hold_ptr| {
        hold_ptr.* = held;
    }

    if (binding.callback) |callback| callback(self, binding.callback_data);
}

fn cursorCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), c.glfwGetWindowUserPointer(window.?).?));

    const dx = x - self.last_mouse_position[0];
    const dy = y - self.last_mouse_position[1];

    self.last_mouse_position = .{ x, y };

    self.game_input.angle[1] -= @floatCast(f32, dx) * 0.022 * 0.006;
    self.game_input.angle[0] -= @floatCast(f32, dy) * 0.022 * 0.006;

    self.game_input.angle[1] = @mod(self.game_input.angle[1], std.math.pi * 2);
    self.game_input.angle[0] = std.math.clamp(self.game_input.angle[0], 0.0, std.math.pi);
}

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), c.glfwGetWindowUserPointer(window.?).?));

    _ = mods;

    c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);

    if (action == c.GLFW_PRESS) {
        self.bindingSet(.{ .mouse_button = button }, true);
    } else if (action == c.GLFW_RELEASE) {
        self.bindingSet(.{ .mouse_button = button }, false);
    }
}

fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), c.glfwGetWindowUserPointer(window.?).?));

    _ = scancode;
    _ = mods;

    if (action == c.GLFW_PRESS) {
        self.bindingSet(.{ .key = key }, true);
    } else if (action == c.GLFW_RELEASE) {
        self.bindingSet(.{ .key = key }, false);
    }

    if (key == c.GLFW_KEY_ESCAPE) {
        c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
    }
}

fn tick(self: *Self) void {
    const delta = blk: {
        const new_time = c.glfwGetTime();
        const old_time = self.time;

        self.time = new_time;

        break :blk @floatCast(f32, new_time - old_time);
    };

    var framebuffer_size: [2]c_int = undefined;
    c.glfwGetFramebufferSize(self.window, &framebuffer_size[0], &framebuffer_size[1]);

    c.glViewport(0, 0, framebuffer_size[0], framebuffer_size[1]);

    c.glClearColor(0.2, 0.3, 0.6, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);

    var aspect = @intToFloat(f32, framebuffer_size[0]) / @intToFloat(f32, framebuffer_size[1]);

    var ctx: RenderContext = undefined;
    ctx.aspect = aspect;

    self.game_input.movement = .{ 0.0, 0.0 };

    if (self.movement_keys[0]) self.game_input.movement[1] += 1.0;
    if (self.movement_keys[1]) self.game_input.movement[1] -= 1.0;
    if (self.movement_keys[2]) self.game_input.movement[0] -= 1.0;
    if (self.movement_keys[3]) self.game_input.movement[0] += 1.0;

    self.game.input(self.game_input);
    self.game.update(delta);
    self.game.draw(&ctx);

    for (self.game_input.keys_pressed) |*key| {
        key.* = false;
    }

    c.glfwSwapBuffers(self.window);
    c.glfwPollEvents();
}
