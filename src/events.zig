const std = @import("std");

pub const Event = union(enum) {
    close,
    resize: @Vector(2, u32),
};

pub const Queue = struct {
    alloc: std.mem.Allocator,
    buffer: []Event,
    start: usize,
    end: usize,

    pub fn init(alloc: std.mem.Allocator) !Queue {
        return .{
            .alloc = alloc,
            .buffer = try alloc.alloc(Event, 32),
            .start = 0,
            .end = 0,
        };
    }

    pub fn deinit(q: *Queue) void {
        if (q.start != q.end) std.log.warn("deinit called while events still in queue", .{});

        q.alloc.free(q.buffer);
    }

    pub fn push(q: *Queue, event: Event) !void {
        q.buffer[q.end] = event;

        q.end += 1;
        if (q.end >= q.buffer.len) q.end = 0;
        if (q.start == q.end) {
            // should resize
            return error.Failed;
        }
    }

    pub fn peek(q: *Queue) Event {
        std.debug.assert(q.start != q.end);
        return q.buffer[q.start];
    }

    pub fn pop(q: *Queue) Event {
        const result = q.peek();
        q.start += 1;
        if (q.start >= q.buffer.len) q.start = 0;
        return result;
    }

    pub fn pending(q: *Queue) bool {
        return q.start != q.end;
    }
};
