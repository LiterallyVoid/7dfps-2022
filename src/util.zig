const std = @import("std");

pub var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 32 }){};
pub var allocator = gpa.allocator();
