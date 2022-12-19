const std = @import("std");

const c = @import("./c.zig");
const asset = @import("./asset.zig");
const util = @import("./util.zig");

const Self = @This();

buffer: c_uint,

fn read_bytes(into: [*]u8, size: usize, nmemb: usize, from: *[]const u8) callconv(.C) usize {
    var len = size * nmemb;
    if (len > from.*.len) {
        len = from.*.len;
    }

    std.mem.copy(u8, into[0..len], from.*[0..len]);
    from.* = from.*[len..];

    return len;
}

pub fn init(am: *asset.Manager, path: []const u8) !Self {
    var file = try am.openPath(path);
    defer file.close();

    var contents = try file.reader().readAllAlloc(util.allocator, 16 * 1024 * 1024);
    defer util.allocator.free(contents);

    var vf: c.OggVorbis_File = undefined;

    var contents_mutated = contents;

    var err = c.ov_open_callbacks(@ptrCast(?*anyopaque, &contents_mutated), &vf, null, 0, .{
        .read_func = @ptrCast(*const fn(into: ?*anyopaque, size: usize, nmemb: usize, from: ?*anyopaque) callconv(.C) usize, &read_bytes),
        .seek_func = null,
        .close_func = null,
        .tell_func = null,
    });

    if (err != 0) {
        return error.VorbisFailed;
    }

    var channels = c.ov_info(&vf, -1)[0].channels;

    var current_section: c_int = undefined;

    var all_pcm = std.ArrayList(u8).init(util.allocator);
    defer all_pcm.deinit();

    while (true) {
        var pcmout: [4096]u8 = undefined;
        var amt = c.ov_read(&vf, &pcmout, pcmout.len, 0, 2, 1, &current_section);
        if (amt <= 0) break;

        try all_pcm.appendSlice(pcmout[0..@intCast(usize, amt)]);
    }

    const rate = @intCast(c_int, c.ov_info(&vf, -1)[0].rate);

    var fmt = if (channels == 1)
        c.AL_FORMAT_MONO16
        else
        c.AL_FORMAT_STEREO16;

    var buffer: c_uint = undefined;
    c.alGenBuffers(1, &buffer);
    c.alBufferData(buffer, fmt, all_pcm.items.ptr, @intCast(c_int, all_pcm.items.len), rate);

    return Self{
        .buffer = buffer,
    };
}

pub fn deinit(self: Self, am: *asset.Manager) void {
    _ = self;
    _ = am;
}
