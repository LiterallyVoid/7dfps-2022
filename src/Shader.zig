const std = @import("std");

const asset = @import("./asset.zig");
const util = @import("./util.zig");
const linalg = @import("./linalg.zig");
const RenderContext = @import("./RenderContext.zig");

const Texture = @import("./Texture.zig");

const Self = @This();

const c = @import("./c.zig");

pub const OPTIONS = struct {
    pub var ambient_occlusion_quality: u32 = 0;
    pub var shadow_quality: u32 = 2;
};

gl_program: c.GLuint,

const FileAndLineno = struct {
    file: usize,
    line: usize,
};

fn parseInfoLogLine(files: *std.ArrayList([]u8), lines: *std.ArrayList(FileAndLineno), line: []const u8) bool {
    var lineno_end: usize = 0;

    var expanded_lineno: usize = 0;

    var state: enum {
        file,
        line,
    } = .file;

    for (line) |ch, i| {
        if (state == .file and std.ascii.isDigit(ch)) continue;
        if (state == .file and ch == ':') {
            state = .line;
            continue;
        }

        if (state == .line and std.ascii.isDigit(ch)) {
            expanded_lineno *= 10;
            expanded_lineno += (ch - '0');
        }

        if (state == .line and !std.ascii.isDigit(ch)) {
            lineno_end = i;
            break;
        }
    }

    if (expanded_lineno == 0 or lineno_end == 0) return false;

    const flno = lines.items[expanded_lineno - 1];

    std.log.err("{s}:{}{s}", .{ files.items[flno.file], flno.line, line[lineno_end..] });

    return true;
}

fn printInfoLog(path: []const u8, files: *std.ArrayList([]u8), lines: *std.ArrayList(FileAndLineno), info_log: []u8) void {
    std.log.err("log for shader {s}:", .{path});

    var info_lines = std.mem.tokenize(u8, info_log, "\r\n");

    while (info_lines.next()) |line| {
        if (!parseInfoLogLine(files, lines, line)) {
            std.log.err("! {s}", .{line});
        }
    }
}

fn parseIncludes(am: *asset.Manager, files: *std.ArrayList([]u8), lines: *std.ArrayList(FileAndLineno), path: []const u8, writer: anytype) !void {
    const file = try am.openPath(path);
    defer file.close();

    const fileno = files.items.len;
    try files.append(try util.allocator.dupe(u8, path));

    var lineno: usize = 0;

    while (try file.reader().readUntilDelimiterOrEofAlloc(util.allocator, '\n', 64 * 1024)) |line| {
        defer util.allocator.free(line);

        lineno += 1;

        if (!std.mem.startsWith(u8, line, "#include ")) {
            try lines.append(.{
                .file = fileno,
                .line = lineno,
            });

            try writer.writeAll(line);
            try writer.writeByte('\n');
            continue;
        }

        const err: ?[]const u8 = err: {
            const first_quote = std.mem.indexOf(u8, line, "\"") orelse break :err "expected '\"' after #include";

            if ((line.len - 1) == first_quote or line[line.len - 1] != '"')
                break :err "unterminated filename after start of #include string";

            const local_path = line[first_quote + 1 .. line.len - 1];

            const sub_path = try std.mem.concat(util.allocator, u8, &.{
                std.fs.path.dirname(path) orelse ".",
                "/",
                local_path,
            });
            defer util.allocator.free(sub_path);

            try parseIncludes(am, files, lines, sub_path, writer);

            break :err null;
        };

        std.log.err("error while loading glsl {s}:{}: {s}", .{ path, lineno, err orelse continue });
    }
}

pub fn compileStage(am: *asset.Manager, base_path: []const u8, stage: c.GLenum) !c.GLuint {
    var files = std.ArrayList([]u8).init(util.allocator);
    defer {
        for (files.items) |file| {
            util.allocator.free(file);
        }

        files.deinit();
    }

    var lines = std.ArrayList(FileAndLineno).init(util.allocator);
    defer lines.deinit();

    try files.append(try util.allocator.dupe(u8, "<version fragment>"));
    try lines.append(.{
        .file = 0,
        .line = 1,
    });

    const ext = switch (stage) {
        c.GL_VERTEX_SHADER => ".vert",
        c.GL_FRAGMENT_SHADER => ".frag",
        else => unreachable,
    };

    const path = try std.mem.concat(util.allocator, u8, &.{
        base_path,
        ext,
    });
    defer util.allocator.free(path);

    var code = std.ArrayList(u8).init(util.allocator);
    defer code.deinit();

    try code.writer().writeAll("#version 330 core\n");
    try code.writer().print("#define AO_QUALITY {}\n", .{ OPTIONS.ambient_occlusion_quality });
    try code.writer().print("#define SHADOW_QUALITY {}\n", .{ OPTIONS.shadow_quality });
    try parseIncludes(am, &files, &lines, path, code.writer());

    var shader = c.glCreateShader(stage);

    c.glShaderSource(shader, 1, &code.items.ptr, &[_]c_int{@intCast(c_int, code.items.len)});
    c.glCompileShader(shader);

    var info_log_length: c_int = 0;

    c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &info_log_length);

    if (info_log_length > 0) {
        var info_log = try util.allocator.alloc(u8, @intCast(usize, info_log_length - 1));
        defer util.allocator.free(info_log);

        c.glGetShaderInfoLog(shader, info_log_length - 1, null, info_log.ptr);

        printInfoLog(path, &files, &lines, info_log);
    }

    return shader;
}

pub fn init(am: *asset.Manager, base_path: []const u8) !Self {
    const vert = try compileStage(am, base_path, c.GL_VERTEX_SHADER);
    defer c.glDeleteShader(vert);

    const frag = try compileStage(am, base_path, c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(frag);

    const program = c.glCreateProgram();
    c.glAttachShader(program, vert);
    c.glAttachShader(program, frag);
    c.glLinkProgram(program);

    var info_log_length: c_int = 0;

    c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &info_log_length);

    if (info_log_length > 0) {
        var info_log = try util.allocator.alloc(u8, @intCast(usize, info_log_length - 1));
        defer util.allocator.free(info_log);

        c.glGetProgramInfoLog(program, info_log_length - 1, null, info_log.ptr);

        std.log.err("shader {s} info log: {s}", .{ base_path, info_log });
    }

    return .{
        .gl_program = program,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    _ = am;

    c.glDeleteProgram(self.gl_program);
}

pub fn bindRaw(self: Self) void {
    c.glUseProgram(self.gl_program);
}

pub fn bind(self: Self, ctx: *RenderContext) void {
    c.glUseProgram(self.gl_program);

    self.uniformMatrix("u_world_to_camera", ctx.matrix_world_to_camera);
    self.uniformMatrix("u_camera_to_world", ctx.matrix_camera_to_world);
    self.uniformMatrix("u_projection", ctx.matrix_projection);

    if (OPTIONS.shadow_quality > 0) {
        self.uniformMatrix("u_shadow", ctx.matrix_shadow);
        self.uniformTexture("u_shadowmap", 4, ctx.texture_shadow);
    }
}

pub fn uniformFloat(self: Self, comptime name: [:0]const u8, value: f32) void {
    const location = c.glGetUniformLocation(self.gl_program, name.ptr);
    if (location < 0) return;

    c.glUniform1f(location, value);
}

pub fn uniformMatrix(self: Self, comptime name: [:0]const u8, matrix: linalg.Mat4) void {
    const location = c.glGetUniformLocation(self.gl_program, name.ptr);
    if (location < 0) return;

    c.glUniformMatrix4fv(location, 1, c.GL_FALSE, &matrix.data[0][0]);
}

pub fn uniformMatrices(self: Self, comptime name: [:0]const u8, matrices: []const linalg.Mat4) void {
    const location = c.glGetUniformLocation(self.gl_program, name.ptr);
    if (location < 0) return;

    c.glUniformMatrix4fv(location, @intCast(c_int, matrices.len), c.GL_FALSE, &matrices[0].data[0][0]);
}

pub fn uniformTexture(self: Self, comptime name: [:0]const u8, slot: u32, texture: Texture) void {
    texture.bind(slot);

    const location = c.glGetUniformLocation(self.gl_program, name.ptr);
    // Note we still bind the texture! By default, all texture uniforms are
    // bound to slot `0` which means that we don't have to set that uniform.
    if (location < 0) return;

    c.glUniform1i(location, @intCast(c_int, slot));
}
