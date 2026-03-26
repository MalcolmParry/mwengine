const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");

pub const Handle = @This();

semaphore: vk.Semaphore,

pub fn init(device: gpu.Device, initial_value: gpu.Timeline.Value) gpu.Timeline.InitError!gpu.Timeline {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const type_info: vk.SemaphoreTypeCreateInfo = .{
        .semaphore_type = .timeline,
        .initial_value = initial_value,
    };

    const semaphore = device.vk.device.createSemaphore(&.{
        .flags = .{},
        .p_next = &type_info,
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };

    return .{ .vk = .{ .semaphore = semaphore } };
}

pub fn deinit(this: gpu.Timeline, device: gpu.Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroySemaphore(this.vk.semaphore, vk_alloc);
}

pub fn waitMany(info: gpu.Timeline.WaitManyInfo) gpu.Timeline.WaitError!void {
    std.debug.assert(info.timelines.len == info.values.len);
    if (info.timelines.len == 0) return;

    const result = info.device.vk.device.waitSemaphoresKHR(&.{
        .semaphore_count = @intCast(info.timelines.len),
        .p_semaphores = @ptrCast(info.timelines.ptr),
        .p_values = info.values.ptr,
    }, info.timeout_ns) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.DeviceLost => error.DeviceLost,
        error.Unknown => error.Unknown,
    };

    return switch (result) {
        .success => {},
        .timeout => error.Timeout,
        else => unreachable,
    };
}

pub fn getValue(timeline: gpu.Timeline, device: gpu.Device) gpu.Timeline.GetValueError!gpu.Timeline.Value {
    return device.vk.device.getSemaphoreCounterValueKHR(timeline.vk.semaphore) catch |err| return switch (err) {
        error.DeviceLost => error.DeviceLost,
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };
}

pub fn setValue(timeline: gpu.Timeline, device: gpu.Device, value: gpu.Timeline.Value) gpu.Timeline.SetValueError!void {
    device.vk.device.signalSemaphoreKHR(&.{
        .semaphore = timeline.vk.semaphore,
        .value = value,
    }) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };
}
