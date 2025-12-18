const platform = @import("platform.zig");

pub const Event = @import("events.zig").Event;
pub const EventQueue = @import("events.zig").Queue;
pub const math = @import("math.zig");
pub const gpu = @import("gpu.zig");

pub const Window = platform.Window;

comptime {
    _ = math;
}
