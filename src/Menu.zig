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

const Self = @This();

app: *App,
visible: bool,
button_id_last: u32 = 0,
controls_visible: bool = false,
active_binding_control: ?[]const u8 = null,

mouse_just_pressed: bool = false,

// set to `false` BY THE APP
mouse_held: bool = false,

pub fn init(self: *Self, app: *App, am: *asset.Manager) !void {
    _ = am;

    self.* = .{
        .app = app,
        .visible = true,
    };
}

pub fn deinit(self: *Self, am: *asset.Manager) void {
    _ = self;
    _ = am;
}

pub fn handleEsc(self: *Self) void {
    if (self.active_binding_control != null) {
        self.active_binding_control = null;
        return;

    }

    if (self.controls_visible) {
        self.controls_visible = false;
        return;
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
        }

        var sens_ratio: f32 = std.math.log(f32, SENS_BASE, ((sens - SENS_FLOOR) / (SENS_CEIL - SENS_FLOOR)) * SENS_BASE_SCALE + SENS_BASE_OFFSET);

        row.next().fontSize(30.0).text("").pad(.{ 10.0, 5.0 }).fill(.{ 0.0, 0.0 }, .{ 0.5, 0.0 })
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
                row = row.color(.{ 255, 64, 64, 255 });
                current_key = "";
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

        _ = bg.center(.{ 0.0, 0.0 }).background(.{ .color = .{ 0, 0, 0, 64 } });
    }

    if (self.controls_visible) {
        self.controls(into);
        return;
    }

    {
        const menu = into.next();
        defer menu.done();

        menu.rows(.{ .justify = 0.5 });
        menu.next().fontSize(90.0).text("OOPS").pad(.{10.0, 30.0}).center(.{ 0.0, 0.0 }).done();

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
        controls_btn.view.fontSize(30.0).text("CONTROLS").pad(.{5.0, 5.0}).center(.{20.0, 5.0}).done();

        if (controls_btn.press) self.controls_visible = true;

        if (self.app.has_started_game) {
            const play_btn = self.button(menu.next());
            if (play_btn.hover) {
                _ = play_btn.view.color(.{ 255, 64, 64, 255 });
            } else {
                _ = play_btn.view.color(.{ 128, 32, 32, 128 });
            }
            play_btn.view.fontSize(30.0).text("RESTART").pad(.{10.0, 10.0}).center(.{20.0, 5.0}).done();
            if (play_btn.press) {
                self.hide();
                self.app.restartGame();
            }
        }

        // spacer! :))
        menu.next().fontSize(45.0).text("").done();
    }
}
