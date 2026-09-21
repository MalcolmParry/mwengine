const std = @import("std");
const gpu = @import("../gpu.zig");
const vk = @import("vulkan");
const MemoryRegion = @import("Device.zig").MemoryRegion;

const Buffer = @This();
pub const Handle = Buffer;

buffer: vk.Buffer,
memory: vk.DeviceMemory,
memory_offset: gpu.Size,
memory_size: gpu.Size,

pub fn init(device: gpu.Device, info: gpu.Buffer.InitInfo) gpu.Buffer.InitError!gpu.Buffer {
    const vk_alloc: ?*vk.AllocationCallbacks = null;

    const vk_usage: vk.BufferUsageFlags = .{
        .vertex_buffer_bit = info.usage.vertex,
        .index_buffer_bit = info.usage.index,
        .uniform_buffer_bit = info.usage.uniform,
        .transfer_src_bit = info.usage.src,
        .transfer_dst_bit = info.usage.dst,
        .storage_buffer_bit = info.usage.storage,
        .indirect_buffer_bit = info.usage.indirect_cmd,
    };

    const buffer = device.vk.device.createBuffer(&.{
        .size = info.size,
        .usage = vk_usage,
        .sharing_mode = .exclusive,
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.InvalidOpaqueCaptureAddressKHR,
        error.Unknown,
        => error.Unknown,
    };
    errdefer device.vk.device.destroyBuffer(buffer, vk_alloc);

    const properties: vk.MemoryPropertyFlags = switch (info.loc) {
        .host => .{ .host_coherent_bit = true },
        .device => .{ .device_local_bit = true },
    };

    const memory_region = try device.vk.allocateMemory(device.vk.device.getBufferMemoryRequirements(buffer), properties, info.usage.mapped);
    errdefer device.vk.freeMemory(memory_region);
    device.vk.device.bindBufferMemory(buffer, memory_region.memory, memory_region.offset) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.InvalidOpaqueCaptureAddressKHR,
        error.Unknown,
        => error.Unknown,
    };

    const mapping = if (memory_region.mapping) |ptr| ptr + memory_region.offset else null;

    return .{
        .size = info.size,
        .mapping_ptr = mapping,
        .impl = .{ .vk = .{
            .buffer = buffer,
            .memory = memory_region.memory,
            .memory_offset = memory_region.offset,
            .memory_size = memory_region.size,
        } },
    };
}

pub fn deinit(buffer: gpu.Buffer, device: gpu.Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const impl = &buffer.impl.vk;
    device.vk.device.destroyBuffer(impl.buffer, vk_alloc);
    device.vk.freeMemory(.{
        .memory = impl.memory,
        .offset = impl.memory_offset,
        .size = impl.memory_size,
        .mapping = buffer.mapping_ptr,
    });
}

pub fn debugLabel(buffer: gpu.Buffer, device: gpu.Device, name: [:0]const u8) void {
    if (device.vk.instance.maybe_debug_messenger == null) return;
    device.vk.device.setDebugUtilsObjectNameEXT(&.{
        .object_type = .buffer,
        .object_handle = @intFromEnum(buffer.impl.vk.buffer),
        .p_object_name = name,
    }) catch {};
}
