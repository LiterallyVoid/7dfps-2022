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
const App = @import("./App.zig");
const Sound = @import("./Sound.zig");

const Self = @This();

app: *App,
visible: bool,
button_id_last: u32 = 0,
graphics_visible: bool = false,
controls_visible: bool = false,
credits_visible: bool = false,
active_binding_control: ?[]const u8 = null,

mouse_just_pressed: bool = false,

// set to `false` BY THE APP
mouse_held: bool = false,

sound_menu: *Sound,
sound_click: *Sound,

pub fn init(self: *Self, app: *App, am: *asset.Manager) !void {
    self.* = .{
        .app = app,
        .visible = true,
        .sound_menu = try am.load(Sound, "sounds/ui-menu.ogg"),
        .sound_click = try am.load(Sound, "sounds/ui-click.ogg"),
    };
}

pub fn deinit(self: *Self, am: *asset.Manager) void {
    am.drop(self.sound_menu);
    am.drop(self.sound_click);
}

pub fn handleEsc(self: *Self) void {
    self.app.playSound(self.sound_menu, .{});

    if (self.active_binding_control != null) {
        self.active_binding_control = null;
        return;

    }

    if (self.controls_visible) {
        self.controls_visible = false;
        return;
    }

    if (self.credits_visible) {
        self.credits_visible = false;
        return;
    }

    if (self.graphics_visible) {
        self.graphics_visible = false;
    }

    if (self.visible) {
        self.hide();
        return;
    }

    self.visible = true;
}

fn hide(self: *Self) void {
    self.visible = false;
    c.glfwSetInputMode(self.app.window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);

    self.app.has_started_game = true;
}

const Button = struct {
    view: *Inter.Viewport,
    hover: bool = false,
    press: bool = false,
    hold: bool = false,
};

fn button(self: *Self, viewport: *Inter.Viewport) Button {
    viewport.id = self.button_id_last;
    self.button_id_last += 1;

    if (viewport.inter.hover == viewport.id) {
        _ = viewport.color(.{ 255, 255, 255, 255 });
        if (self.mouse_just_pressed) {
            self.app.playSound(self.sound_click, .{});
            return .{ .view = viewport, .hover = true, .press = true, .hold = true };
        } else if (self.mouse_held) {
            return .{ .view = viewport, .hover = true, .hold = true };
        }

        return .{ .view = viewport, .hover = true };
    }

    _ = viewport.color(.{ 128, 128, 128, 128 });
    return .{ .view = viewport };
}

pub fn onButtonPressed(self: *Self, btn: App.Button) void {
    if (btn == .key and btn.key == c.GLFW_KEY_ESCAPE) {
        self.handleEsc();
        return;
    }

    if (self.active_binding_control) |actively_binding| {
        self.app.createBinding(btn, actively_binding);
        self.active_binding_control = null;
        return;
    }

    if (btn == .mouse_button and btn.mouse_button == 0) {
        self.mouse_just_pressed = true;
        self.mouse_held = true;
    }
}

pub fn graphics(self: *Self, into: *Inter.Viewport) void {
    const menu = into.next();
    defer menu.done();

    const Option = struct {
        name: []const u8,
        ptr: *u32,
    };

    const options = [_]Option{
        .{ .name = "SSAO", .ptr = &Shader.OPTIONS.ambient_occlusion_quality },
        .{ .name = "Shadows", .ptr = &Shader.OPTIONS.shadow_quality },
    };

    menu.rows(.{ .justify = 0.5 });

    menu.next().fontSize(50.0).text("GRAPHICS").pad(.{ 10.0, 0.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().pad(.{0.0, 10.0}).done();

    for (options) |option| {
        const row = menu.next();

        row.columns(.{ .fill_items = 4 });
        row.next().center(.{ 0.0, 0.0 }).done();
        row.next().fontSize(30.0).text(option.name).pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0}, .{ 1.0, 0.0 }).done();

        const value_str = switch (option.ptr.*) {
            0 => "Off",
            1 => "Low",
            2 => "Medium",
            3 => "High",
            4 => "Ultra",
            else => "idk",
        };

        {
            var value = row.next();
            defer value.done();
            value.columns(.{ .fill_items = 3 });
            const decrease_btn = self.button(value.next());
            decrease_btn.view.fontSize(30.0).text("<").pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0 }, .{ 0.0, 0.0 }).done();
            value.next().fontSize(30.0).text(value_str).pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0 }, .{ 0.5, 0.5 }).done();
            const increase_btn = self.button(value.next());
            increase_btn.view.fontSize(30.0).text(">").pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0 }, .{ 1.0, 0.0 }).done();

            if (decrease_btn.press and option.ptr.* > 0) {
                option.ptr.* -= 1;
                self.app.needs_recompile = true;
            }

            if (increase_btn.press and option.ptr.* < 4) {
                option.ptr.* += 1;
                self.app.needs_recompile = true;
            }
        }
        row.done();
    }
}

pub fn credits(self: *Self, into: *Inter.Viewport) void {
    _ = self;

    const menu = into.next();
    defer menu.done();

    menu.rows(.{ .justify = 0.5 });

    menu.next().fontSize(50.0).text("CREDITS").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().pad(.{0.0, 5.0}).done();
    menu.next().fontSize(15.0).text("Open-source software bundled: GLFW, libogg, libvorbis, and OpenAL Soft").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().fontSize(10.0).text("Licenses available at /licenses/").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().pad(.{ 0.0, 10.0 }).done();
    menu.next().fontSize(15.0).text("Models created and animated in Blender; Written in Zig").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().pad(.{ 0.0, 10.0 }).done();
    menu.next().fontSize(15.0).text("Some textures from Polyhaven").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().fontSize(10.0).text("https://polyhaven.com").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().pad(.{ 0.0, 10.0 }).done();
    menu.next().fontSize(15.0).text("Sounds from SONNISS GDC Audio packs").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().fontSize(10.0).text("https://sonniss.com/gameaudiogdc").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().pad(.{ 0.0, 10.0 }).done();
    menu.next().fontSize(5.0).text("The font is Overpass.").pad(.{ 0.0, 5.0 }).center(.{ 0.0, 0.0 }).done();
}

pub fn controls(self: *Self, into: *Inter.Viewport) void {
    const menu = into.next();
    defer menu.done();

    const actions = [_][2][]const u8 {
        .{ "game/forward", "Forward" },
        .{ "game/back", "Back" },
        .{ "game/left", "Left" },
        .{ "game/right", "Right" },
        .{ "game/jump", "Jump" },
        .{ "game/attack", "Attack" },
        .{ "game/reload", "Reload" },
        .{ "game/quick_melee", "Quick Melee" },
    };

    menu.rows(.{ .justify = 0.5 });

    menu.next().fontSize(50.0).text("CONTROLS").pad(.{ 10.0, 0.0 }).center(.{ 0.0, 0.0 }).done();
    menu.next().pad(.{0.0, 10.0}).done();

    {
        var sigdigs: u32 = 4;
        var decdigs: u32 = 5;
        var sens: f32 = self.app.sensitivity;
        var sens_buf: [32]u8 = undefined;
        var sens_buf2: [32]u8 = undefined;
        const sens_digits = std.fmt.bufPrint(&sens_buf, "{}", .{ @floatToInt(u32, sens * std.math.pow(f32, 10.0, @intToFloat(f32, decdigs))) }) catch "??";

        var dot = if (sens_digits.len < decdigs) 0 else (sens_digits.len - decdigs);

        var sens_str: []const u8 = undefined;

        if (dot < 1) {
            sens_str = std.fmt.bufPrint(&sens_buf2, "0.{s}", .{sens_digits[dot..sigdigs]}) catch "??";
        } else if (dot < sigdigs) {
            sens_str = std.fmt.bufPrint(&sens_buf2, "{s}.{s}", .{sens_digits[0..dot], sens_digits[dot..sigdigs]}) catch "??";
        } else {
            sens_str = std.fmt.bufPrint(&sens_buf2, "{s}", .{sens_digits[0..dot]}) catch "??";
        }

        var text_row = menu.next();

        if (self.app.inter.hover == self.button_id_last and self.mouse_held) {
            _ = text_row.color(.{255, 128, 128, 255});
        }

        text_row.columns(.{ .fill_items = 4 });
        text_row.next().center(.{ 0.0, 0.0 }).done();
        text_row.next().fontSize(30.0).text("Sensitivity").pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0}, .{ 1.0, 0.0 }).done();
        text_row.next().fontSize(30.0).text(sens_str).pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0 }, .{ 0.5, 0.0 }).done();
        text_row.done();

        const row_btn = self.button(menu.next());
        var row = row_btn.view;
        defer row.done();
        row.columns(.{ .fill_items = 1 });

        const SENS_FLOOR = 0.1;
        const SENS_CEIL = 1000.0;

        const SENS_BASE = 10000.0;
        const SENS_BASE_OFFSET = 1.0;
        const SENS_BASE_SCALE = SENS_BASE - SENS_BASE_OFFSET;

        if (row_btn.hold) {
            const ratio = std.math.clamp(self.app.inter.hover_mouse[0] * 2.0 - 0.5, 0.0, 1.0);
            sens = ((std.math.pow(f32, SENS_BASE, ratio) - SENS_BASE_OFFSET) / SENS_BASE_SCALE) * (SENS_CEIL - SENS_FLOOR) + SENS_FLOOR;
            self.app.sensitivity = sens;
            self.app.didSetSensitivity();
        }

        var sens_ratio: f32 = std.math.log(f32, SENS_BASE, ((sens - SENS_FLOOR) / (SENS_CEIL - SENS_FLOOR)) * SENS_BASE_SCALE + SENS_BASE_OFFSET);

        row.next().fontSize(20.0).text("").pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 10.0 }, .{ 0.5, 0.0 })
            .color(.{255, 255, 255, 255}).sliderRect(0.25, 0.25 + sens_ratio * 0.5)
            .color(.{64, 64, 64, 64}).sliderRect(0.25, 0.75)
            .done();
    }

    inline for (actions) |action| {
        const row_btn = self.button(menu.next());

        if (row_btn.press and self.active_binding_control == null) {
            self.active_binding_control = action[0];
        }

        var row = row_btn.view;
        defer row.done();

        row.columns(.{ .fill_items = 4 });

        var upper_buf: [256]u8 = undefined;

        var current_key =
            if (self.app.bindings_reverse.get(action[0])) |current_binding| current_binding.name()
            else "Not Bound";

        for (current_key) |ch, i| {
            upper_buf[i] = std.ascii.toUpper(ch);
        }

        current_key = upper_buf[0..current_key.len];

        if (self.active_binding_control) |active_control| {
            if (std.mem.eql(u8, active_control, action[0])) {
                row = row.color(.{ 255, 128, 128, 255 });
                current_key = "(waiting...)";
            } else {
                row = row.color(.{ 128, 128, 128, 128 });
            }
        }

        row.next().center(.{ 0.0, 0.0 }).done();
        row.next().fontSize(30.0).text(action[1]).pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0}, .{ 1.0, 0.0 }).done();
        row.next().fontSize(30.0).text(current_key).pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0}, .{ 0.5, 0.0 }).done();
    }
}

pub fn drawUI(self: *Self, into: *Inter.Viewport) void {
    defer self.mouse_just_pressed = false;

    self.button_id_last = 0;

    if (!self.visible) return;

    {
        const bg = into.next();
        defer bg.done();

        _ = bg.center(.{ 0.0, 0.0 }).background(.{ .color = .{ 0, 0, 0, 128 } });
    }

    if (self.controls_visible) {
        self.controls(into);
        return;
    }

    if (self.graphics_visible) {
        self.graphics(into);
        return;
    }

    if (self.credits_visible) {
        self.credits(into);
        return;
    }

    {
        const menu = into.next();
        defer menu.done();

        menu.rows(.{ .justify = 0.5 });
        menu.next().fontSize(90.0).text("8.06DFPS").pad(.{10.0, 30.0}).center(.{ 0.0, 0.0 }).done();

        if (!self.app.has_started_game) {
            const play_btn = self.button(menu.next());
            play_btn.view.fontSize(60.0).text("PLAY").pad(.{10.0, 10.0}).center(.{20.0, 5.0}).done();

            if (play_btn.press) {
                self.hide();
                self.app.has_started_game = true;
            }
        } else {
            const resume_btn = self.button(menu.next());
            resume_btn.view.fontSize(60.0).text("RESUME").pad(.{10.0, 10.0}).center(.{20.0, 5.0}).done();
            if (resume_btn.press) {
                self.hide();
            }
        }

        const controls_btn = self.button(menu.next());
        controls_btn.view.fontSize(30.0).text("CONTROLS").pad(.{5.0, 2.0}).center(.{20.0, 5.0}).done();

        if (controls_btn.press) self.controls_visible = true;

        const graphics_btn = self.button(menu.next());
        graphics_btn.view.fontSize(30.0).text("GRAPHICS").pad(.{5.0, 2.0}).center(.{20.0, 5.0}).done();

        if (graphics_btn.press) self.graphics_visible = true;

        const credits_btn = self.button(menu.next());
        credits_btn.view.fontSize(30.0).text("CREDITS").pad(.{5.0, 2.0}).center(.{20.0, 5.0}).done();

        if (credits_btn.press) self.credits_visible = true;

        if (self.app.has_started_game) {
            const play_btn = self.button(menu.next());
            if (play_btn.hover) {
                _ = play_btn.view.color(.{ 255, 32, 32, 255 });
            } else {
                _ = play_btn.view.color(.{ 128, 32, 32, 128 });
            }
            play_btn.view.fontSize(30.0).text("RESTART").pad(.{10.0, 2.0}).center(.{20.0, 5.0}).done();
            if (play_btn.press) {
                self.hide();
                self.app.restartGame();
            }
        }

        const quit_btn = self.button(menu.next());
        if (quit_btn.hover) {
            _ = quit_btn.view.color(.{ 255, 32, 32, 255 });
        } else {
            _ = quit_btn.view.color(.{ 128, 32, 32, 128 });
        }
        quit_btn.view.fontSize(30.0).text("QUIT").pad(.{10.0, 2.0}).center(.{20.0, 5.0}).done();
        if (quit_btn.press) {
            c.glfwSetWindowShouldClose(self.app.window, c.GLFW_TRUE);
        }

        // spacer! :))
        menu.next().fontSize(45.0).text("").done();
    }
}
