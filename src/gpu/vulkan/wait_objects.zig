const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");

pub const Semaphore = struct {
    semaphore: vk.Semaphore,

    pub const Handle = Semaphore;

    pub fn init(device: gpu.Device) !gpu.Semaphore {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const semaphore = try device.vk.device.createSemaphore(&.{
            .flags = .{},
        }, vk_alloc);

        return .{ .vk = .{ .semaphore = semaphore } };
    }

    pub fn deinit(this: gpu.Semaphore, device: gpu.Device) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroySemaphore(this.vk.semaphore, vk_alloc);
    }

    pub fn nativesFromSlice(these: []const gpu.Semaphore) ?[*]const vk.Semaphore {
        if (these.len == 0) return null;
        return @ptrCast(these);
    }
};

pub const Fence = struct {
    fence: vk.Fence,

    pub const Handle = Fence;

    pub fn init(device: gpu.Device, signaled: bool) !gpu.Fence {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const fence = try device.vk.device.createFence(&.{
            .flags = .{
                .signaled_bit = signaled,
            },
        }, vk_alloc);

        return .{ .vk = .{ .fence = fence } };
    }

    pub fn deinit(this: gpu.Fence, device: gpu.Device) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroyFence(this.vk.fence, vk_alloc);
    }

    pub fn reset(this: gpu.Fence, device: gpu.Device) !void {
        try device.vk.device.resetFences(1, @ptrCast(&this.vk.fence));
    }

    pub fn waitMany(these: []const gpu.Fence, device: gpu.Device, how_many: gpu.Fence.WaitForEnum, timeout_ns: ?u64) !void {
        const wait_all: vk.Bool32 = switch (how_many) {
            .single => .false,
            .all => .true,
        };
        return switch (try device.vk.device.waitForFences(@intCast(these.len), nativesFromSlice(these).?, wait_all, timeout_ns orelse std.math.maxInt(u64))) {
            .success => {},
            .timeout => error.Timeout,
            else => unreachable,
        };
    }

    pub fn checkSignaled(this: gpu.Fence, device: gpu.Device) !bool {
        return switch (try device.vk.device.getFenceStatus(this.vk.fence)) {
            .success => true,
            .not_ready => false,
            else => unreachable,
        };
    }

    pub fn nativesFromSlice(these: []const gpu.Fence) ?[*]const vk.Fence {
        if (these.len == 0) return null;
        return @ptrCast(these);
    }
};
