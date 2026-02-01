const std = @import("std");

pub const Event = union(enum) {
    close,
    resize: @Vector(2, u32),
    key_down: Keycode,
    key_up: Keycode,
    key_repeat: Keycode,
};

pub const Queue = struct {
    alloc: std.mem.Allocator,
    buffer: []Event,
    start: usize,
    end: usize,

    pub fn init(alloc: std.mem.Allocator) !Queue {
        return .{
            .alloc = alloc,
            .buffer = try alloc.alloc(Event, 512),
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

pub const Keycode = enum {
    space,
    apostrophe,
    comma,
    minus,
    period,
    slash,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    semicolon,
    equal,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    left_bracket,
    backslash,
    right_bracket,
    grave_accent,
    world_1,
    world_2,

    escape,
    enter,
    tab,
    backspace,
    insert,
    delete,
    right,
    left,
    down,
    up,
    page_up,
    page_down,
    home,
    end,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    F13,
    F14,
    F15,
    F16,
    F17,
    F18,
    F19,
    F20,
    F21,
    F22,
    F23,
    F24,
    F25,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equal,
    left_shift,
    left_control,
    left_alt,
    left_super,
    right_shift,
    right_control,
    right_alt,
    right_super,
    menu,
    unknown,
};
