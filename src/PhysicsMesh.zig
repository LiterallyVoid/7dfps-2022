const std = @import("std");

const linalg = @import("./linalg.zig");
const util = @import("./util.zig");

const Self = @This();

pub const Impact = struct {
    time: f32,
    plane: linalg.Vec4,

    offset: linalg.Vec3 = linalg.Vec3.zero(),

    pub fn join(self: Impact, other: ?Impact) Impact {
        if ((other orelse return self).time < self.time) return other.?;
        return self;
    }
};

const PackedBrush = extern struct {
    next_brush: ?*PackedBrush,
    planes_count: u32,
    non_bevel_planes: u32,

    fn planesWithoutBevels(self: *PackedBrush) [][4]f32 {
        return @ptrCast([*][4]f32, @ptrCast([*]PackedBrush, self) + 1)[0..self.non_bevel_planes];
    }

    fn planes(self: *PackedBrush) [][4]f32 {
        return @ptrCast([*][4]f32, @ptrCast([*]PackedBrush, self) + 1)[0..self.planes_count];
    }
};

const Block = struct {
    brushes: ?*PackedBrush,
};

const Brush = struct {
    planes: [][4]f32,
    non_bevel_planes: u32,

    fn planesWithoutBevels(self: *PackedBrush) [][4]f32 {
        return self.planes[0..self.non_bevel_planes];
    }
};

/// Returns the smallest vector to take the box at origin `point` outside of the brush specified by `planes`.
fn brushNudge(planes: [][4]f32, point: linalg.Vec3, half_extents: linalg.Vec3) ?Impact {
    var closest: f32 = -std.math.inf(f32);
    var closest_nudge = linalg.Vec3.zero();
    var closest_plane = linalg.Vec4.zero();

    for (planes) |plane_raw| {
        const plane = linalg.Vec4 { .data = plane_raw };

        var height = plane.dotPoint(point) - plane.xyz().abs().dot(half_extents);

        if (height >= -0.000001) return null;

        if (height > closest) {
            closest = height;
            closest_nudge = plane.xyz().mulScalar(-height);
            closest_plane = plane;
        }
    }

    return .{
        .time = 0.0,
        .offset = closest_nudge,
        .plane = closest_plane,
    };
}

/// Returns the ratio of how far `point` can move in `direction`
fn brushTraceLine(planes: [][4]f32, point: linalg.Vec3, half_extents: linalg.Vec3, direction: linalg.Vec3) ?Impact {
    var enter_time = -std.math.inf(f32);
    var exit_time = std.math.inf(f32);

    var enter_plane: linalg.Vec4 = undefined;

    for (planes) |plane_raw| {
        const plane = linalg.Vec4 { .data = plane_raw };

        var height = plane.dotPoint(point) - plane.xyz().abs().dot(half_extents);
        var speed = plane.xyz().dot(direction);

        if (speed == 0.0) {
            if (height < 0) continue;
            return null;
        }

        var time = height / -speed;

        if (speed > 0.0) {
            exit_time = std.math.min(exit_time, time);
            continue;
        }

        if (time > enter_time) {
            enter_time = time;
            enter_plane = plane;
        }

        if (enter_time > exit_time + 0.00001) return null;
    }

    if (enter_time < 0.0) return null;
    if (enter_time > 1.0) return null;
    if (enter_time > exit_time + 0.00001) return null;

    return Impact{
        .time = enter_time,
        .plane = enter_plane,
    };
}

const BLOCKSIZE: f32 = 4.0;

blocks: []Block,
blocks_size: [3]usize,

origin: linalg.Vec3,

fn packBrushes(brushes: []const Brush) !Block {
    if (brushes.len == 0) return Block{
        .brushes = null,
    };

    var total_bytes: usize = 0;

    for (brushes) |brush| {
        total_bytes += @sizeOf(PackedBrush);
        total_bytes += @sizeOf([4]f32) * brush.planes.len;
    }

    var data = try util.allocator.allocWithOptions(u8, total_bytes, @alignOf(PackedBrush), null);
    errdefer data.deinit();

    var first: ?*PackedBrush = null;

    var fixup: *?*PackedBrush = &first;

    var current_byte: usize = 0;

    for (brushes) |brush| {
        const packed_brush: *PackedBrush = @ptrCast(*PackedBrush, @alignCast(@alignOf(PackedBrush), &data[current_byte]));
        current_byte += @sizeOf(PackedBrush);

        packed_brush.* = .{
            .next_brush = null,
            .planes_count = @intCast(u32, brush.planes.len),
            .non_bevel_planes = brush.non_bevel_planes,
        };

        for (brush.planes) |plane| {
            std.mem.copy(u8, data.ptr[current_byte..current_byte + @sizeOf([4]f32)], std.mem.asBytes(&plane));
            current_byte += @sizeOf([4]f32);
        }

        fixup.* = packed_brush;
        fixup = &packed_brush.next_brush;
    }

    std.debug.assert(total_bytes == current_byte);

    return Block{
        .brushes = first,
    };
}

const BlockIterator = struct {
    blocks_size: [3]usize,

    index: usize,
    size: [3]usize,

    accumulators: [3]isize = .{ 0, 0, 0 },

    done: bool = false,

    pub fn new(blocks_size: [3]usize, start: [3]usize, size: [3]usize) BlockIterator {
        var self = BlockIterator {
            .blocks_size = blocks_size,

            .index = undefined,

            .size = size,
        };

        self.index =
            self.stride(0) * start[0] +
            self.stride(1) * start[1] +
            self.stride(2) * start[2];

        return self;
    }

    fn stride(self: BlockIterator, comptime axis: usize) usize {
        if (axis == 0) {
            return self.blocks_size[1] * self.blocks_size[2];
        } else if (axis == 1) {
            return self.blocks_size[2];
        } else if (axis == 2) {
            return 1;
        } else {
            unreachable;
        }
    }

    fn advance(self: *BlockIterator) void {
        inline for (@as([3]void, undefined)) |_, i| {
            const axis = 2 - i;

            self.index += self.stride(axis);
            self.accumulators[axis] += 1;

            if (@intCast(usize, self.accumulators[axis]) >= self.size[axis]) {
                if (axis == 0) {
                    self.done = true;
                    break;
                }

                self.index -= self.stride(axis) * self.size[axis];
                self.accumulators[axis] = 0;
            } else {
                break;
            }
        }
    }

    fn next(self: *BlockIterator) ?usize {
        if (self.done) return null;

        const initial = self.index;

        self.advance();

        return initial;
    }
};

test "PhysicsMesh/BlockIterator single" {
    var iterator = BlockIterator.new(.{ 2, 2, 2 }, .{ 1, 1, 1 }, .{ 1, 1, 1 });

    try std.testing.expectEqual(iterator.next(), 7);
    try std.testing.expectEqual(iterator.next(), null);
}

test "PhysicsMesh/BlockIterator eight" {
    var iterator = BlockIterator.new(.{ 2, 2, 2 }, .{ 0, 0, 0 }, .{ 2, 2, 2 });

    try std.testing.expectEqual(iterator.next(), 0);
    try std.testing.expectEqual(iterator.next(), 1);
    try std.testing.expectEqual(iterator.next(), 2);
    try std.testing.expectEqual(iterator.next(), 3);
    try std.testing.expectEqual(iterator.next(), 4);
    try std.testing.expectEqual(iterator.next(), 5);
    try std.testing.expectEqual(iterator.next(), 6);
    try std.testing.expectEqual(iterator.next(), 7);
    try std.testing.expectEqual(iterator.next(), null);
}

test "PhysicsMesh/BlockIterator +x" {
    var iterator = BlockIterator.new(.{ 2, 2, 2 }, .{ 0, 0, 0 }, .{ 2, 1, 1 });

    try std.testing.expectEqual(iterator.next(), 0);
    try std.testing.expectEqual(iterator.next(), 4);
    try std.testing.expectEqual(iterator.next(), null);
}

fn addBevelPlane(planes: *std.ArrayList([4]f32), triangle: [3]linalg.Vec3, normal: linalg.Vec3) !void {
    if (normal.smallerThan(0.1)) return;

    for (planes.items) |plane| {
        if (linalg.Vec3.fromArray(f32, plane[0..3].*).sub(normal).smallerThan(0.001)) {
            return;
        }
    }

    var max: f32 = -std.math.inf(f32);
    for (triangle) |point| {
        max = std.math.max(max, point.dot(normal));
    }

    try planes.append(normal.xyzw(-max).toArray(f32));
}

pub fn init(triangles: [][3][3]f32) !Self {
    var mins: [3]f32 = triangles[0][0];
    var maxs: [3]f32 = triangles[0][0];

    for (triangles) |triangle| {
        for (triangle) |point| {
            for (point) |elem, i| {
                mins[i] = std.math.min(mins[i], elem);
                maxs[i] = std.math.max(maxs[i], elem);
            }
        }
    }

    var brushes = std.ArrayList(Brush).init(util.allocator);
    defer {
        for (brushes.items) |brush| {
            util.allocator.free(brush.planes);
        }

        brushes.deinit();
    }

    triangles: for (triangles) |triangle| {
        var planes = std.ArrayList([4]f32).init(util.allocator);
        errdefer planes.deinit();

        var points: [3]linalg.Vec3 = undefined;
        var edges: [3]linalg.Vec3 = undefined;

        for (triangle) |vertex, i| {
            points[i] = linalg.Vec3 { .data = vertex };
        }

        for (points) |point, i| {
            const next = points[(i + 1) % 3];

            const edge = next.sub(point);

            edges[i] = edge.normalized();
        }

        var normal = points[1].sub(points[0]).cross(points[2].sub(points[0]));

        // If the area is this small, either it is tiny (i.e. we don't care) or
        // its points are nearly colinear (i.e. we don't care). Toss the
        // triangle whence it came.
        if (normal.smallerThan(0.00000001)) {
            continue :triangles;
        }

        normal = normal.normalized();

        {
            const normal_plane = normal.xyzw(-normal.dot(points[0]));
            try planes.append(normal_plane.toArray(f32));
            try planes.append(normal_plane.mulScalar(-1.0).toArray(f32));
        }

        for (edges) |edge, i| {
            const edge_normal = edge.cross(normal).normalized();

            try planes.append(edge_normal.xyzw(-edge_normal.dot(points[i])).toArray(f32));
        }

        var axes = [_]linalg.Vec3{
            linalg.Vec3.new(1.0, 0.0, 0.0),
            linalg.Vec3.new(0.0, 1.0, 0.0),
            linalg.Vec3.new(0.0, 0.0, 1.0),
            linalg.Vec3.new(-1.0, 0.0, 0.0),
            linalg.Vec3.new(0.0, -1.0, 0.0),
            linalg.Vec3.new(0.0, 0.0, -1.0),
        };

        var non_bevel_planes = @intCast(u32, planes.items.len);

        for (axes) |axis| {
            try addBevelPlane(&planes, points, axis);
        }

        for (edges) |edge| {
            for (axes) |axis| {
                try addBevelPlane(&planes, points, edge.cross(axis).normalized());
            }
        }

        try brushes.append(.{
            .planes = planes.toOwnedSlice(),
            .non_bevel_planes = non_bevel_planes,
        });
    }

    var self: Self = undefined;

    self.origin = linalg.Vec3 { .data = mins };

    for (mins) |min_axis, i| {
        const max_axis = maxs[i];

        self.blocks_size[i] = @floatToInt(usize, @floor((max_axis - min_axis) / BLOCKSIZE)) + 1;
    }

    self.blocks = try util.allocator.alloc(Block, self.blocks_size[0] * self.blocks_size[1] * self.blocks_size[2]);

    var it = BlockIterator.new(self.blocks_size, .{ 0, 0, 0 }, self.blocks_size);

    var brushes_filtered = std.ArrayList(Brush).init(util.allocator);
    defer brushes_filtered.deinit();

    var blocks_occupied: usize = 0;

    while (true) {
        // accumulator is equal to position, if it starts at {0, 0, 0}
        const position = it.accumulators;
        const index = it.next() orelse break;

        var half_extents = linalg.Vec3.new(1.0, 1.0, 1.0).mulScalar(BLOCKSIZE / 2.0);
        var margin = linalg.Vec3.new(1.0, 1.0, 1.0).mulScalar(0.25);

        var origin = self.origin.add(linalg.Vec3.fromArray(isize, position).mulScalar(BLOCKSIZE)).add(half_extents);

        brushes_filtered.items.len = 0;

        for (brushes.items) |brush| {
            if (brushNudge(brush.planes, origin, half_extents.add(margin))) |_| {
                try brushes_filtered.append(brush);
            }
        }

        self.blocks[index] = try packBrushes(brushes_filtered.items);

        if (brushes_filtered.items.len > 0) {
            blocks_occupied += 1;
        }
    }

    std.log.err("created blockmap of size {any} ({}/{} occupied)", .{ self.blocks_size, blocks_occupied, self.blocks.len });
    return self;
}

pub fn deinit(self: Self) void {
    for (self.blocks) |block| {
        const brushes = block.brushes orelse continue;

        var last = brushes;
        while (last.next_brush) |next| {
            last = next;
        }

        var last_planes = last.planes();
        var last_plane = &last_planes[last_planes.len - 1];

        var len = (@ptrToInt(last_plane) - @ptrToInt(brushes)) + @sizeOf([4]f32);

        var bytes = @ptrCast([*]align(@alignOf(PackedBrush)) u8, brushes)[0..len];

        util.allocator.free(bytes);
    }

    util.allocator.free(self.blocks);
}

fn regionIterator(self: Self, mins: linalg.Vec3, maxs: linalg.Vec3) BlockIterator {
    var bounds = linalg.IVec3.fromArray(usize, self.blocks_size);

    var start = mins.sub(self.origin)
        .divScalar(BLOCKSIZE)
        .floor()
        .toVector(linalg.IVec3)
        .maxScalar(0)
        .min(bounds);

    var end = maxs.sub(self.origin)
        .divScalar(BLOCKSIZE)
        .ceil()
        .toVector(linalg.IVec3)
        .maxScalar(0)
        .min(bounds);

    return BlockIterator.new(self.blocks_size, start.toArray(usize), end.sub(start).toArray(usize));
}

pub fn traceLine(self: Self, point: linalg.Vec3, half_extents: linalg.Vec3, direction: linalg.Vec3) ?Impact {
    var impact: ?Impact = null;

    var mins = point.sub(half_extents).add(direction.minScalar(0.0));
    var maxs = point.add(half_extents).add(direction.maxScalar(0.0));

    var it = self.regionIterator(mins, maxs);

    while (it.next()) |i| {
        var brush = self.blocks[i].brushes;

        while (brush) |next| : (brush = next.next_brush) {
            if (brushTraceLine(next.planes(), point, half_extents, direction)) |new_impact| {
                impact = new_impact.join(impact);
            }

            brush = next.next_brush;
        }
    }

    return impact;
}

pub fn nudge(self: Self, point: linalg.Vec3, half_extents: linalg.Vec3) ?Impact {
    var impact: ?Impact = null;

    var new_point = point;

    var mins = point.sub(half_extents);
    var maxs = point.add(half_extents);

    var it = self.regionIterator(mins, maxs);

    while (it.next()) |i| {
        var brush = self.blocks[i].brushes;

        while (brush) |next| : (brush = next.next_brush) {
            if (brushNudge(next.planes(), new_point, half_extents)) |new_impact| {
                if (impact) |old_impact| {
                    impact = .{
                        .time = 0.0,
                        .offset = old_impact.offset.add(new_impact.offset),
                        .plane = new_impact.plane,
                    };
                } else {
                    impact = new_impact;
                }

                new_point = point.add(impact.?.offset);
            }

            brush = next.next_brush;
        }
    }

    return impact;
}
