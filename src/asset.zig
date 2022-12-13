const std = @import("std");

const util = @import("./util.zig");

pub const Manager = struct {
    prefix: []const u8,

    pub fn openPath(self: *Manager, local_path: []const u8) !std.fs.File {
        const path = try std.mem.concat(util.allocator, u8, &.{
            self.prefix,
            "/",
            local_path,
        });
        defer util.allocator.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.log.err("error while trying to load asset from {s}: {}", .{ path, err });
            return err;
        };

        return file;
    }

    pub fn load(self: *Manager, comptime T: type, data: anytype) !*T {
        const box = try util.allocator.create(T);
        errdefer util.allocator.destroy(box);

        box.* = try T.init(self, data);

        return box;
    }

    pub fn drop(self: *Manager, instance: anytype) void {
        _ = @typeInfo(@TypeOf(instance)).Pointer.child; // `instance` should be a pointer to `T`.
        _ = @typeInfo(@typeInfo(@TypeOf(instance)).Pointer.child).Struct; // `instance` should be a pointer to `T`.

        instance.deinit(self);

        util.allocator.destroy(instance);
    }
};
