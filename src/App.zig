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
const Entity = @import("./Entity.zig");
const Inter = @import("./Inter.zig");
const Menu = @import("./Menu.zig");
const Texture = @import("./Texture.zig");
const Sound = @import("./Sound.zig");

const Framebuffer = @import("./Framebuffer.zig");

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

needs_recompile: bool,

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

settings_write_timer: f32 = -1.0,

fb_main: Framebuffer,
fb_shadow: Framebuffer,
fb_ssao: Framebuffer,

fullscreen_mesh: Mesh,
fullscreen_shader: *Shader,
ssao_shader: *Shader,

sound_sources: [MAX_SOUNDS]SoundSource,
current_sound: usize,

const MAX_SOUNDS = 128;

const SoundSource = struct {
    pub const Options = struct {
        entity: ?*Entity = null,
        gain: f32 = 1.0,
    };

    source: c.GLuint,
    options: Options,

    playing: bool,

    pub fn create() SoundSource {
        var source: c.GLuint = undefined;

        c.alGenSources(1, &source);

        return SoundSource {
            .source = source,
            .options = undefined,
            .playing = false,
        };
    }

    pub fn tick(self: *SoundSource) void {
        var state: c.ALint = undefined;
        c.alGetSourcei(self.source, c.AL_SOURCE_STATE, &state);

        if (state != c.AL_PLAYING) {
            c.alSourceStop(self.source);
            self.playing = false;
            return;
        }

        if (self.options.entity) |entity| {
            c.alSourcefv(self.source, c.AL_POSITION, &entity.origin.data[0]);
            c.alSourcefv(self.source, c.AL_VELOCITY, &entity.velocity.data[0]);

            if (!entity.alive) {
                c.alSource3f(self.source, c.AL_VELOCITY, 0.0, 0.0, 0.0);
                self.options.entity = null;
            }
        }

        //c.alSourcef(self.source, c.AL_GAIN, self.options.gain);
    }

    pub fn play(self: *SoundSource, sound: *Sound, options: Options) void {
        c.alSourcei(self.source, c.AL_BUFFER, @intCast(c_int, sound.buffer));

        self.options = options;

        if (self.options.entity == null) {
            c.alSourcei(self.source, c.AL_SOURCE_RELATIVE, c.AL_TRUE);
            c.alSourcef(self.source, c.AL_REFERENCE_DISTANCE, 1.0);
            c.alSourcef(self.source, c.AL_ROLLOFF_FACTOR, 1.0);
        } else {
            c.alSourcei(self.source, c.AL_SOURCE_RELATIVE, c.AL_FALSE);
            c.alSourcef(self.source, c.AL_REFERENCE_DISTANCE, 3.0);
        }

        self.tick();

        c.alSourcePlay(self.source);

        self.playing = true;
    }
};

pub fn playSound(self: *Self, sound: *Sound, options: SoundSource.Options) void {
    var first = &self.sound_sources[self.current_sound];
    var source = first;

    while (source.playing) {
        self.current_sound = (self.current_sound + 1) % MAX_SOUNDS;
        source = &self.sound_sources[self.current_sound];

        if (source == first) return;
    }

    source.play(sound, options);
}

const FullscreenMeshVertex = struct {
    position: [2]f32,
};

const SETTINGS_MAGIC = 0x7D00DEAD;
const ALL_ACTIONS = [_][]const u8 {
    "game/forward",
    "game/back",
    "game/left",
    "game/right",
    "game/jump",
    "game/attack",
    "game/reload",
    "game/quick_melee",
};

pub fn writeSettings(self: *Self) !void {
    var file = try std.fs.cwd().createFile("settings.bin", .{});
    defer file.close();

    try file.writer().writeIntLittle(u32, SETTINGS_MAGIC);
    try file.writer().writeIntLittle(u32, @bitCast(u32, self.sensitivity));

    for (ALL_ACTIONS) |action| {
        const button = self.bindings_reverse.get(action) orelse continue;
        std.log.info("Wrote binding {s} for {s}", .{ button.name(), action });

        if (button == .key) {
            try file.writer().writeIntLittle(u8, 0);
            try file.writer().writeIntLittle(i32, button.key);
        } else {
            try file.writer().writeIntLittle(u8, 1);
            try file.writer().writeIntLittle(i32, button.mouse_button);
        }
    }

    try file.writer().writeIntLittle(u32, Shader.OPTIONS.ambient_occlusion_quality);
    try file.writer().writeIntLittle(u32, Shader.OPTIONS.shadow_quality);
}

pub fn readSettings(self: *Self) !void {
    var file = try std.fs.cwd().openFile("settings.bin", .{});
    defer file.close();

    var reader = file.reader();

    if (SETTINGS_MAGIC != try reader.readIntLittle(u32)) return error.WrongMagic;
    self.sensitivity = @bitCast(f32, try reader.readIntLittle(u32));

    for (ALL_ACTIONS) |action| {
        var button: Button = undefined;

        const ty = try reader.readIntLittle(u8);
        if (ty == 0) {
            button = .{ .key = try reader.readIntLittle(i32), };
        } else {
            button = .{ .mouse_button = try reader.readIntLittle(i32), };
        }

        std.log.info("Read binding {s} for {s}", .{ button.name(), action });
        self.createBindingRaw(button, action);
    }

    Shader.OPTIONS.ambient_occlusion_quality = std.math.clamp(try reader.readIntLittle(u32), 0, 4);
    Shader.OPTIONS.shadow_quality = std.math.clamp(try reader.readIntLittle(u32), 0, 4);
}

fn afterGameRestarted(self: *Self) void {
    self.game_input.angle = .{ std.math.pi * 0.5, self.game.player.angle.data[2] - std.math.pi * 1.5 };
}

pub fn restartGame(self: *Self) void {
    self.game.deinit();
    self.game.init(self, &self.asset_manager, "maps/sandbox.map") catch unreachable;
    self.afterGameRestarted();
}

pub fn init(self: *Self) !void {
    self.movement_keys = .{ false, false, false, false };
    self.sensitivity = 1.0;
    self.last_mouse_position = .{ 0.0, 0.0 };

    self.window = c.glfwCreateWindow(640, 480, "8.06DFPS", null, null) orelse return error.GLFWWindowFailed;
    errdefer c.glfwDestroyWindow(self.window);

    c.glfwMakeContextCurrent(self.window);
    if (c.gladLoadGL(c.glfwGetProcAddress) == 0) return error.OpenGLLoadFailed;

    self.asset_manager = asset.Manager.init("data");
    //errdefer self.asset_manager.deinit();

    try Inter.init(&self.inter, &self.asset_manager);
    try self.menu.init(self, &self.asset_manager);
    self.needs_recompile = false;

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

    try self.actions.put("game/quick_melee", .{
        .press_ptr = &self.game_input.keys_pressed[3],
        .hold_ptr = &self.game_input.keys_held[3],
    });

    self.createBindingRaw(.{ .key = c.GLFW_KEY_W }, "game/forward");
    self.createBindingRaw(.{ .key = c.GLFW_KEY_S }, "game/back");
    self.createBindingRaw(.{ .key = c.GLFW_KEY_A }, "game/left");
    self.createBindingRaw(.{ .key = c.GLFW_KEY_D }, "game/right");
    self.createBindingRaw(.{ .key = c.GLFW_KEY_R }, "game/reload");
    self.createBindingRaw(.{ .key = c.GLFW_KEY_SPACE }, "game/jump");
    self.createBindingRaw(.{ .mouse_button = 0 }, "game/attack");
    self.createBindingRaw(.{ .mouse_button = 1 }, "game/quick_melee");

    c.glfwSetWindowUserPointer(self.window, self);

    _ = c.glfwSetCursorPosCallback(self.window, cursorCallback);
    _ = c.glfwSetMouseButtonCallback(self.window, mouseButtonCallback);
    _ = c.glfwSetKeyCallback(self.window, keyCallback);
    _ = c.glfwSetWindowFocusCallback(self.window, focusCallback);

    self.readSettings() catch |e| std.log.err("error while reading settings: {}", .{ e });

    if (c.glfwRawMouseMotionSupported() != 0) {
        c.glfwSetInputMode(self.window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
    }

    try self.game.init(self, &self.asset_manager, "maps/sandbox.map");

    self.afterGameRestarted();

    self.fb_main = Framebuffer.init(&.{
        c.GL_RGB8,
        c.GL_RGB8,
        }, true);
    self.fb_ssao = Framebuffer.init(&.{
        c.GL_R8,
        }, false);
    self.fb_shadow = Framebuffer.init(&.{}, true);
    self.fullscreen_mesh = Mesh.init(.{ .static = true, .indexed = false }, FullscreenMeshVertex);
    self.fullscreen_mesh.upload(FullscreenMeshVertex, &.{
        .{
            .position = .{ -1.0, -1.0 },
        },
        .{
            .position = .{ 3.0, -1.0 },
        },
        .{
            .position = .{ -1.0, 3.0 },
        },
    });
    self.fullscreen_shader = try self.asset_manager.load(Shader, "shaders/fullscreen");
    self.ssao_shader = try self.asset_manager.load(Shader, "shaders/ssao");

    self.current_sound = 0;
    for (self.sound_sources) |*source| {
        source.* = SoundSource.create();
    }
}

pub fn deinit(self: *Self) void {
    self.fb_main.deinit();
    self.fb_shadow.deinit();
    self.asset_manager.drop(self.fullscreen_shader);
    self.asset_manager.drop(self.ssao_shader);

    self.actions.deinit();
    self.bindings.deinit();
    self.bindings_reverse.deinit();
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

pub fn didSetSensitivity(self: *Self) void {
    self.settings_write_timer = 1.0;
}

pub fn createBinding(self: *Self, button: Button, binding: []const u8) void {
    self.createBindingRaw(button, binding);

    self.writeSettings() catch |e| {
        std.log.err("error while writing settings: {}", .{ e });
    };
}

pub fn createBindingRaw(self: *Self, button: Button, binding: []const u8) void {
    if (self.bindings_reverse.get(binding)) |current_button| {
        _ = self.bindings.remove(current_button);
    }

    if (self.bindings.get(button)) |current_binding| {
        _ = self.bindings_reverse.remove(current_binding);
        _ = self.bindings.remove(button);
    }

    self.bindings_reverse.put(binding, button) catch unreachable;

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
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), c.glfwGetWindowUserPointer(window.?).?));

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
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), c.glfwGetWindowUserPointer(window.?).?));

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
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), c.glfwGetWindowUserPointer(window.?).?));

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
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), c.glfwGetWindowUserPointer(window.?).?));

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

    if (self.settings_write_timer > 0.0) {
        self.settings_write_timer -= delta;
        if (self.settings_write_timer < 0) {
            self.writeSettings() catch |e| std.log.err("error while writing settings to file: {}", .{ e });
        }
    }

    var framebuffer_size: [2]c_int = undefined;
    c.glfwGetFramebufferSize(self.window, &framebuffer_size[0], &framebuffer_size[1]);

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
        self.game.update(delta * 0.4);
    }

    if (Shader.OPTIONS.shadow_quality > 0) {
        const sizes = [_]usize{
            0,
            512,
            1024,
            2048,
            4096,
        };
        const size = sizes[Shader.OPTIONS.shadow_quality];
        self.fb_shadow.resize(.{ size, size });
        self.fb_shadow.bind();
        c.glClear(c.GL_DEPTH_BUFFER_BIT);

        self.game.drawShadow(&ctx);

        ctx.texture_shadow = .{ .gl_texture = self.fb_shadow.gl_tex_depth.? };
    }

    self.fb_main.resize(.{
        @intCast(usize, framebuffer_size[0]),
        @intCast(usize, framebuffer_size[1]),
    });
    self.fb_main.bind();

    c.glColorMaski(1, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE);
    c.glClearColor(1.0, 0.9, 0.8, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    c.glColorMaski(0, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE, c.GL_FALSE);
    c.glColorMaski(1, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE);
    c.glClearColor(0.5, 0.5, 0.5, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);

    c.glColorMaski(0, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE, c.GL_TRUE);

    self.game.draw(&ctx);
    self.game.drawTransparent(&ctx);

    c.glDisable(c.GL_DEPTH_TEST);

    if (Shader.OPTIONS.ambient_occlusion_quality > 0) {
        var ao_divisor: usize = 2;
        if (Shader.OPTIONS.ambient_occlusion_quality == 0) {
            ao_divisor = 4;
        }
        if (Shader.OPTIONS.ambient_occlusion_quality == 1) {
            ao_divisor = 3;
        }
        self.fb_ssao.resize(.{
            @intCast(usize, framebuffer_size[0]) / ao_divisor,
            @intCast(usize, framebuffer_size[1]) / ao_divisor,
        });
        self.fb_ssao.bind();

        self.ssao_shader.bindRaw();
        self.ssao_shader.uniformTexture("u_screen", 0, Texture { .gl_texture = self.fb_main.gl_tex_colors[0].? });
        self.ssao_shader.uniformTexture("u_screen_normal", 1, Texture { .gl_texture = self.fb_main.gl_tex_colors[1].? });
        self.ssao_shader.uniformTexture("u_screen_depth", 2, Texture { .gl_texture = self.fb_main.gl_tex_depth.? });
        self.ssao_shader.uniformMatrix("u_projection", ctx.matrix_projection);
        self.ssao_shader.uniformMatrix("u_projection_inverse", ctx.matrix_projection.inverse());
        self.ssao_shader.uniformFloat("u_time", @floatCast(f32, @mod(c.glfwGetTime(), 1.0)));
        self.fullscreen_mesh.draw(0, 3);
    }

    c.glBindFramebuffer(c.GL_FRAMEBUFFER, 0);
    c.glViewport(0, 0, framebuffer_size[0], framebuffer_size[1]);

    self.fullscreen_shader.bindRaw();
    self.fullscreen_shader.uniformTexture("u_screen", 0, Texture { .gl_texture = self.fb_main.gl_tex_colors[0].? });
    self.fullscreen_shader.uniformTexture("u_screen_normal", 1, Texture { .gl_texture = self.fb_main.gl_tex_colors[1].? });
    self.fullscreen_shader.uniformTexture("u_screen_depth", 2, Texture { .gl_texture = self.fb_main.gl_tex_depth.? });

    if (Shader.OPTIONS.ambient_occlusion_quality > 0) {
        self.fullscreen_shader.uniformTexture("u_screen_ssao", 3, Texture { .gl_texture = self.fb_ssao.gl_tex_colors[0].? });
    }
    self.fullscreen_shader.uniformMatrix("u_projection", ctx.matrix_projection);
    self.fullscreen_shader.uniformMatrix("u_projection_inverse", ctx.matrix_projection.inverse());
    self.fullscreen_shader.uniformFloat("u_time", @floatCast(f32, @mod(c.glfwGetTime(), 1.0)));
    self.fullscreen_mesh.draw(0, 3);

    if (self.needs_recompile) {
        self.asset_manager.recompileShaders();
        self.needs_recompile = false;
        self.writeSettings() catch |e| std.log.err("error while writing settings to file: {}", .{ e });
    }

    {
        var screen_ = self.inter.begin(.{
            @intToFloat(f32, framebuffer_size[0]),
            @intToFloat(f32, framebuffer_size[1]),
        });

        const mouse_position: [2]f32 = .{
            @floatCast(f32, self.last_mouse_position[0]),
            @floatCast(f32, self.last_mouse_position[1]),
        };

        var content_scale = blk: {
            const desired_size: [2]f32 = .{ 800.0, 600.0 };

            var scale: f32 = 100.0;

            for (desired_size) |size_in_axis, i| {
                var needed_scale = screen_.size_hint[i].? / size_in_axis;
                scale = std.math.min(scale, needed_scale);
            }

            break :blk scale;
        };

        var screen = screen_.contentScale(content_scale);
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

        for (self.sound_sources) |*source| {
            if (!source.playing) continue;
            source.tick();
        }

        c.alListenerfv(c.AL_POSITION, &self.game.player.origin.data[0]);

        var orientation = [_]linalg.Vec3{
            ctx.matrix_camera_to_world.multiplyVector(linalg.Vec4.new(0.0, 0.0, -1.0, 0.0)).xyz(),
            ctx.matrix_camera_to_world.multiplyVector(linalg.Vec4.new(0.0, 1.0, 0.0, 0.0)).xyz(),
        };

        c.alListenerfv(c.AL_ORIENTATION, &orientation[0].data[0]);
        c.alListenerfv(c.AL_VELOCITY, &self.game.player.velocity.data[0]);

        if (!self.game.player.alive) {
            c.alListener3f(c.AL_VELOCITY, 0.0, 0.0, 0.0);
        }
    }

    for (self.game_input.keys_pressed) |*key| {
        key.* = false;
    }

    c.glfwSwapBuffers(self.window);
    c.glfwPollEvents();
}
