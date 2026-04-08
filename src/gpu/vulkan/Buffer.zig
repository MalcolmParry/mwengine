const std = @import("std");
const gpu = @import("../gpu.zig");
const vk = @import("vulkan");
const MemoryRegion = @import("Device.zig").MemoryRegion;

const Buffer = @This();
pub const Handle = *Buffer;

buffer: vk.Buffer,
memory_region: MemoryRegion,
size_: gpu.Size,

pub fn init(device: gpu.Device, info: gpu.Buffer.InitInfo) gpu.Buffer.InitError!gpu.Buffer {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const this = try info.alloc.create(Buffer);
    errdefer info.alloc.destroy(this);

    const vk_usage: vk.BufferUsageFlags = .{
        .vertex_buffer_bit = info.usage.vertex,
        .index_buffer_bit = info.usage.index,
        .uniform_buffer_bit = info.usage.uniform,
        .transfer_src_bit = info.usage.src,
        .transfer_dst_bit = info.usage.dst,
    };

    this.size_ = info.size;
    this.buffer = device.vk.device.createBuffer(&.{
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
    errdefer device.vk.device.destroyBuffer(this.buffer, vk_alloc);

    const properties: vk.MemoryPropertyFlags = switch (info.loc) {
        .host => .{ .host_coherent_bit = true },
        .device => .{ .device_local_bit = true },
    };

    this.memory_region = try device.vk.allocateMemory(device.vk.device.getBufferMemoryRequirements(this.buffer), properties);
    errdefer device.vk.freeMemory(this.memory_region);
    device.vk.device.bindBufferMemory(this.buffer, this.memory_region.memory, this.memory_region.offset) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.InvalidOpaqueCaptureAddressKHR,
        error.Unknown,
        => error.Unknown,
    };

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Buffer, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyBuffer(this.vk.buffer, vk_alloc);
    device.vk.freeMemory(this.vk.memory_region);
    alloc.destroy(this.vk);
}

pub fn size(this: gpu.Buffer) gpu.Size {
    return this.vk.size_;
}

pub const Region = struct {
    pub fn map(this: gpu.Buffer.Region, device: gpu.Device) gpu.Buffer.MapError![]u8 {
        const result = device.vk.device.mapMemory(this.buffer.vk.memory_region.memory, this.offset, this.size, .{}) catch |err| return switch (err) {
            error.OutOfHostMemory => error.OutOfMemory,
            error.OutOfDeviceMemory => error.OutOfDeviceMemory,
            error.MemoryMapFailed => error.MemoryMapFailed,
            error.Unknown => error.Unknown,
        };

        const data = result.?;
        const many_ptr: [*]u8 = @ptrCast(data);
        return many_ptr[0..this.size];
    }

    pub fn unmap(this: gpu.Buffer.Region, device: gpu.Device) void {
        device.vk.device.unmapMemory(this.buffer.vk.memory_region.memory);
    }
};
