const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");

pub const Semaphore = struct {
    _semaphore: vk.Semaphore,

    pub fn init(device: gpu.Device) !@This() {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const semaphore = try device.vk.device.createSemaphore(&.{
            .flags = .{},
        }, vk_alloc);

        return .{ ._semaphore = semaphore };
    }

    pub fn deinit(this: @This(), device: gpu.Device) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroySemaphore(this._semaphore, vk_alloc);
    }

    pub fn _nativesFromSlice(these: []const @This()) ?[*]const vk.Semaphore {
        if (these.len == 0) return null;
        return @ptrCast(these);
    }
};

pub const Fence = struct {
    _fence: vk.Fence,

    pub fn init(device: gpu.Device, signaled: bool) !@This() {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const fence = try device.vk.device.createFence(&.{
            .flags = .{
                .signaled_bit = signaled,
            },
        }, vk_alloc);

        return .{ ._fence = fence };
    }

    pub fn deinit(this: @This(), device: gpu.Device) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroyFence(this._fence, vk_alloc);
    }

    pub fn reset(this: @This(), device: gpu.Device) !void {
        try device.vk.device.resetFences(1, @ptrCast(&this._fence));
    }

    pub const WaitForEnum = enum { single, all };

    pub fn waitMany(these: []const @This(), device: gpu.Device, how_many: WaitForEnum, timeout_ns: ?u64) !void {
        const wait_all: vk.Bool32 = switch (how_many) {
            .single => .false,
            .all => .true,
        };
        return switch (try device.vk.device.waitForFences(@intCast(these.len), _nativesFromSlice(these).?, wait_all, timeout_ns orelse std.math.maxInt(u64))) {
            .success => {},
            .timeout => error.Timeout,
            else => unreachable,
        };
    }

    pub fn wait(this: @This(), device: gpu.Device, timeout_ns: ?u64) !void {
        return waitMany(&.{this}, device, .all, timeout_ns);
    }

    pub fn checkSignaled(this: @This(), device: gpu.Device) bool {
        return switch (try device.vk.device.getFenceStatus(this._fence)) {
            .success => true,
            .not_ready => false,
            else => unreachable,
        };
    }

    pub fn _nativesFromSlice(these: []const @This()) ?[*]const vk.Fence {
        if (these.len == 0) return null;
        return @ptrCast(these);
    }
};
