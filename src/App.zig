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
const Menu = @import("./Menu.zig");

const Self = @This();

pub const Button = union(enum) {
    mouse_button: c_int,
    key: c_int,

    pub fn name(self: Button) []const u8 {
        if (self == .key) {
            if (self.key == c.GLFW_KEY_SPACE) return "SPACE";
            if (self.key == c.GLFW_KEY_ENTER) return "RETURN";

            if (c.glfwGetKeyName(self.key, 0)) |name_real| {
                return std.mem.span(name_real);
            }

            return "UNKNOWN";
        } else {
            return switch (self.mouse_button) {
                0 => "LMB",
                1 => "RMB",
                2 => "MMB",
                3 => "M4",
                4 => "M5",
                5 => "M6",
                6 => "M7",
                7 => "M8",
                8 => "M9",
                9 => "M10",
                10 => "M11",
                11 => "M12",
                12 => "M13",
                13 => "M14",
                else => "M??",
            };
        }
    }
};

pub const Action = struct {
    press_ptr: ?*bool = null,
    hold_ptr: ?*bool = null,

    callback: ?*const fn (app: *Self, data: ?*anyopaque) void = null,
    callback_data: ?*anyopaque = null,
};

window: *c.GLFWwindow,
asset_manager: asset.Manager,

time: f64,
last_mouse_position: [2]f64,

actions: std.StringHashMap(Action),

bindings: std.AutoHashMap(Button, []const u8),
bindings_reverse: std.StringHashMap(Button),

sensitivity: f32,

movement_keys: [4]bool,

has_started_game: bool = false,
game: Game,
game_input: Game.Input,

inter: Inter,

menu: Menu,

pub fn restartGame(self: *Self) void {
    self.game.deinit();
    self.game.init(&self.asset_manager, "maps/sandbox.map") catch unreachable;
}

pub fn init(self: *Self) !void {
    self.movement_keys = .{ false, false, false, false };
    self.sensitivity = 1.0;
    self.last_mouse_position = .{ 0.0, 0.0 };

    self.window = c.glfwCreateWindow(640, 480, "7dfps 2022", null, null) orelse return error.GLFWWindowFailed;
    errdefer c.glfwDestroyWindow(self.window);

    c.glfwMakeContextCurrent(self.window);
    if (c.gladLoadGL(c.glfwGetProcAddress) == 0) return error.OpenGLLoadFailed;

    self.asset_manager = asset.Manager.init("data");
    //errdefer self.asset_manager.deinit();

    try Inter.init(&self.inter, &self.asset_manager);
    try self.menu.init(self, &self.asset_manager);

    try self.game.init(&self.asset_manager, "maps/sandbox.map");

    if (c.glfwRawMouseMotionSupported() != 0) {
        c.glfwSetInputMode(self.window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
    }

    c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
    c.glEnable(c.GL_DEPTH_TEST);

    self.time = c.glfwGetTime();

    self.actions = std.StringHashMap(Action).init(util.allocator);

    self.bindings = std.AutoHashMap(Button, []const u8).init(util.allocator);
    self.bindings_reverse = std.StringHashMap(Button).init(util.allocator);

    try self.actions.put("game/forward", .{
        .hold_ptr = &self.movement_keys[0],
    });

    try self.actions.put("game/back", .{
        .hold_ptr = &self.movement_keys[1],
    });

    try self.actions.put("game/left", .{
        .hold_ptr = &self.movement_keys[2],
    });

    try self.actions.put("game/right", .{
        .hold_ptr = &self.movement_keys[3],
    });

    try self.actions.put("game/jump", .{
        .press_ptr = &self.game_input.keys_pressed[0],
        .hold_ptr = &self.game_input.keys_held[0],
    });

    try self.actions.put("game/attack", .{
        .press_ptr = &self.game_input.keys_pressed[1],
        .hold_ptr = &self.game_input.keys_held[1],
    });

    try self.actions.put("game/reload", .{
        .press_ptr = &self.game_input.keys_pressed[2],
        .hold_ptr = &self.game_input.keys_held[2],
    });

    self.createBinding(.{ .key = c.GLFW_KEY_W }, "game/forward");
    self.createBinding(.{ .key = c.GLFW_KEY_S }, "game/back");
    self.createBinding(.{ .key = c.GLFW_KEY_A }, "game/left");
    self.createBinding(.{ .key = c.GLFW_KEY_D }, "game/right");
    self.createBinding(.{ .key = c.GLFW_KEY_R }, "game/reload");
    self.createBinding(.{ .key = c.GLFW_KEY_SPACE }, "game/jump");
    self.createBinding(.{ .mouse_button = 0 }, "game/attack");

    c.glfwSetWindowUserPointer(self.window, self);

    _ = c.glfwSetCursorPosCallback(self.window, cursorCallback);
    _ = c.glfwSetMouseButtonCallback(self.window, mouseButtonCallback);
    _ = c.glfwSetKeyCallback(self.window, keyCallback);
    _ = c.glfwSetWindowFocusCallback(self.window, focusCallback);
}

pub fn deinit(self: *Self) void {
    self.bindings.deinit();
    self.game.deinit();
    self.menu.deinit(&self.asset_manager);
    self.inter.deinit(&self.asset_manager);
    self.asset_manager.deinit();
    c.glfwDestroyWindow(self.window);
}

pub fn run(self: *Self) void {
    while (c.glfwWindowShouldClose(self.window) == 0) {
        self.tick();
    }
}

pub fn createBinding(self: *Self, button: Button, binding: []const u8) void {
    if (self.bindings_reverse.get(binding)) |current_button| {
        _ = self.bindings.remove(current_button);
    }

    self.bindings_reverse.put(binding, button) catch unreachable;

    if (self.bindings.get(button)) |current_binding| {
        _ = self.bindings_reverse.remove(current_binding);
        _ = self.bindings.remove(button);
    }

    self.bindings.put(button, binding) catch unreachable;
}

fn bindingSet(self: *Self, button: Button, held: bool) void {
    const action_name = self.bindings.get(button) orelse return;
    const action = self.actions.get(action_name) orelse unreachable;

    if (held) {
        if (action.press_ptr) |press_ptr| {
            press_ptr.* = true;
        }
    }

    if (action.hold_ptr) |hold_ptr| {
        hold_ptr.* = held;
    }

    if (action.callback) |callback| callback(self, action.callback_data);
}

fn cursorCallback(window: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), c.glfwGetWindowUserPointer(window.?).?));

    const dx = x - self.last_mouse_position[0];
    const dy = y - self.last_mouse_position[1];

    self.last_mouse_position = .{ x, y };

    if (!self.menu.visible) {
        self.game_input.angle[1] -= @floatCast(f32, dx) * 0.022 * self.sensitivity * 0.001;
        self.game_input.angle[0] -= @floatCast(f32, dy) * 0.022 * self.sensitivity * 0.001;

        self.game_input.angle[1] = @mod(self.game_input.angle[1], std.math.pi * 2);
        self.game_input.angle[0] = std.math.clamp(self.game_input.angle[0], 0.0, std.math.pi);
    }
}

fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), c.glfwGetWindowUserPointer(window.?).?));

    _ = mods;

    if (self.menu.visible) {
        if (action == c.GLFW_PRESS) {
            self.menu.onButtonPressed(.{ .mouse_button = button });
        } else if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
            self.menu.mouse_held = false;
        }
    } else {
        if (action == c.GLFW_PRESS) {
            self.bindingSet(.{ .mouse_button = button }, true);
        } else if (action == c.GLFW_RELEASE) {
            self.bindingSet(.{ .mouse_button = button }, false);
        }
    }
}

fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), c.glfwGetWindowUserPointer(window.?).?));

    _ = scancode;
    _ = mods;

    if (self.menu.visible) {
        if (action == c.GLFW_PRESS) {
            self.menu.onButtonPressed(.{ .key = key });
        }
    } else {
        if (action == c.GLFW_PRESS) {
            if (key == c.GLFW_KEY_ESCAPE) {
                c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
                self.onBlur();
            }
            self.bindingSet(.{ .key = key }, true);
        } else if (action == c.GLFW_RELEASE) {
            self.bindingSet(.{ .key = key }, false);
        }
    }
}

fn focusCallback(window: ?*c.GLFWwindow, focused: c_int) callconv(.C) void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(*Self), c.glfwGetWindowUserPointer(window.?).?));

    if (focused != c.GLFW_TRUE) {
        self.menu.visible = true;
        c.glfwSetInputMode(self.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
        self.onBlur();
    }
}

fn onBlur(self: *Self) void {
    var it = self.bindings.iterator();

    self.menu.mouse_held = false;

    while (it.next()) |entry| {
        self.bindingSet(entry.key_ptr.*, false);
    }

    self.menu.visible = true;
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

    if (!self.menu.visible) {
        self.game.update(delta);
    }

    self.game.draw(&ctx);

    {
        var screen_ = self.inter.begin(.{
            @intToFloat(f32, framebuffer_size[0]),
            @intToFloat(f32, framebuffer_size[1]),
        });

        const mouse_position: [2]f32 = .{
            @floatCast(f32, self.last_mouse_position[0]),
            @floatCast(f32, self.last_mouse_position[1]),
        };

        var screen = screen_.contentScale(2.0);
        defer self.inter.flush(screen, mouse_position);
        defer screen.done();

        {
            const game = screen.next();
            defer game.done();

            self.game.drawUI(game);
        }

        {
            const menu = screen.next();
            defer menu.done();

            self.menu.drawUI(menu);
        }
    }

    for (self.game_input.keys_pressed) |*key| {
        key.* = false;
    }

    c.glfwSwapBuffers(self.window);
    c.glfwPollEvents();
}
