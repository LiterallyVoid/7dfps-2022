const std = @import("std");

pub var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 32 }){};
pub var allocator = gpa.allocator();

pub fn angleWrap(val: f32) f32 {
    return @mod(val + std.math.pi, std.math.pi * 2) - std.math.pi;
}
