const std = @import("std");

const util = @import("./util.zig");
const Shader = @import("./Shader.zig");

fn AssetWithHeader(comptime T: type) type {
    return struct {
        header: LoadedAssetHeader,
        data: T,
    };
}

const LoadedAssetHeader = struct {
    key: []const u8,
    references: u32,
};

pub const Manager = struct {
    prefix: []const u8,

    assets: std.StringHashMap(*LoadedAssetHeader),

    pub fn init(prefix: []const u8) Manager {
        return .{
            .prefix = prefix,
            .assets = std.StringHashMap(*LoadedAssetHeader).init(util.allocator),
        };
    }

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
        var suffix: []const u8 = undefined;
        var suffix_needs_free = false;
        defer if (suffix_needs_free) util.allocator.free(suffix);

        if (@hasDecl(T, "serializeInfo")) {
            suffix = T.serializeInfo(data);
            suffix_needs_free = true;
        } else {
            suffix = data;
        }

        var key_buf: [1024]u8 = undefined;

        const key = try std.fmt.bufPrint(&key_buf, "{s}/{s}", .{ @typeName(T), suffix });

        if (self.assets.get(key)) |header| {
            const with_header = @fieldParentPtr(AssetWithHeader(T), "header", header);

            with_header.header.references += 1;

            return &with_header.data;
        }

        std.log.info("load asset {s}", .{ key });

        var key_alloc = try util.allocator.dupe(u8, key);
        errdefer util.allocator.free(key_alloc);

        const box = try util.allocator.create(AssetWithHeader(T));
        errdefer util.allocator.destroy(box);

        box.header = .{
            .key = key_alloc,
            .references = 1,
        };

        box.data = try T.init(self, data);
        errdefer box.data.deinit(self);

        try self.assets.put(key_alloc, &box.header);

        return &box.data;
    }

    pub fn drop(self: *Manager, instance: anytype) void {
        const T = @typeInfo(@TypeOf(instance)).Pointer.child; // `instance` should be a pointer to `T`.
        _ = @typeInfo(T).Struct; // `instance` should be a pointer to `T`.

        const with_header = @fieldParentPtr(AssetWithHeader(T), "data", instance);

        with_header.header.references -= 1;

        if (with_header.header.references == 0) {
            _ = self.assets.remove(with_header.header.key);

            instance.deinit(self);

            util.allocator.free(with_header.header.key);

            util.allocator.destroy(with_header);
        }
    }

    pub fn deinit(self: *Manager) void {
        self.assets.deinit();
    }

    pub fn recompileShaders(self: *Manager) void {
        var it = self.assets.iterator();
        while (it.next()) |entry| {
            if (!std.mem.startsWith(u8, entry.key_ptr.*, "Shader/")) {
                continue;
            }

            const path = entry.key_ptr.*["Shader/".len..];

            const header = entry.value_ptr.*;
            const with_header = @fieldParentPtr(AssetWithHeader(Shader), "header", header);

            with_header.data.deinit(self);
            with_header.data = Shader.init(self, path) catch unreachable;
        }
    }
};
