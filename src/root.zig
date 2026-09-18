const std = @import("std");
const options = @import("options");

pub const Window = if (options.include_windowing) @import("Window.zig") else .{};
pub const math = @import("math.zig");
pub const gpu = if (options.include_gpu) @import("gpu/gpu.zig") else .{};
pub const text = if (options.include_renderer) @import("text.zig") else .{};
pub const ImmediateRenderer = if (options.include_renderer) @import("renderer/Immediate.zig") else .{};

test {
    _ = math;
    _ = gpu;
    _ = @import("gpu/free_list_allocator.zig");
}
