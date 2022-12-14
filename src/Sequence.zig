const std = @import("std");

const Entity = @import("./Entity.zig");

const Self = @This();

pub const MAX_EVENTS = 64;

pub const Event = union(enum) {
    set_flags: u32,
    clear_flags: u32,

    frame_range: struct {
        start: f32,
        end: f32,
        framerate: f32,
    },

    call_function: struct {
        callback: *const fn (entity: *Entity, ctx: *const Entity.TickContext) void,
    },

    replace_with: *const Self,
    restart: void,
};

event_storage: [MAX_EVENTS]Event,
events_data: [MAX_EVENTS]f32,
events_len: usize,

current_event: usize,

flags: u32,

frame: f32,

pub fn init(events: []const Event) Self {
    std.debug.assert(events.len < MAX_EVENTS);

    var self: Self = undefined;

    std.mem.copy(Event, self.event_storage[0..events.len], events);
    self.events_data = [_]f32{0.0} ** MAX_EVENTS;
    self.events_len = events.len;

    self.current_event = 0;
    self.flags = 0;

    self.frame = 0.0;

    return self;
}

fn processEvent(self: *Self, entity: *Entity, ctx: *const Entity.TickContext, time_remaining: f32) ?f32 {
    if (self.current_event >= self.events_len) return null;
    const event = self.event_storage[self.current_event];
    const data = &self.events_data[self.current_event];
    self.current_event += 1;

    switch (event) {
        .set_flags => |flags| {
            self.flags |= flags;
            return time_remaining;
        },
        .clear_flags => |flags| {
            self.flags &= ~flags;
            return time_remaining;
        },
        .frame_range => |range| {
            if (range.framerate > -0.1 and range.framerate < 0.1) {
                self.frame = range.start;

                self.current_event -= 1;

                return null;
            }

            const range_len = @fabs(range.end - range.start);

            const frames_left = range_len - data.* * range.framerate;
            const frames_available = time_remaining * range.framerate;

            if (frames_left > frames_available) {
                data.* += time_remaining;

                if (range.end < range.start) {
                    self.frame = range.start - data.* * range.framerate;
                } else {
                    self.frame = range.start + data.* * range.framerate;
                }

                self.current_event -= 1;

                return null;
            }

            self.frame = range.end;
            return frames_left / range.framerate;
        },
        .call_function => |func_data| {
            func_data.callback(entity, ctx);
            return time_remaining;
        },
        .replace_with => |other_seq| {
            self.* = other_seq.*;
            return time_remaining;
        },
        .restart => {
            self.current_event = 0;
            self.events_data = [1]f32{0.0} ** MAX_EVENTS;
            return time_remaining;
        },
    }
}

pub fn tick(self: *Self, entity: *Entity, ctx: *const Entity.TickContext) void {
    var accumulator = ctx.delta;

    while (self.processEvent(entity, ctx, accumulator)) |time_remaining| {
        accumulator = time_remaining;
    }
}

pub fn flag(self: Self, flags: u32) bool {
    return (self.flags & flags) == flags;
}
