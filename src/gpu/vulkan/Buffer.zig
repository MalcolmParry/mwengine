const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const MemoryRegion = @import("Device.zig").MemoryRegion;

const Buffer = @This();
pub const Handle = *Buffer;

buffer: vk.Buffer,
memory_region: MemoryRegion,
size_: gpu.Size,

pub fn init(device: gpu.Device, info: gpu.Buffer.CreateInfo) !gpu.Buffer {
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
    this.buffer = try device.vk.device.createBuffer(&.{
        .size = info.size,
        .usage = vk_usage,
        .sharing_mode = .exclusive,
    }, vk_alloc);
    errdefer device.vk.device.destroyBuffer(this.buffer, vk_alloc);

    const properties: vk.MemoryPropertyFlags = switch (info.loc) {
        .host => .{ .host_visible_bit = true },
        .device => .{ .device_local_bit = true },
    };

    this.memory_region = try device.vk.allocateMemory(device.vk.device.getBufferMemoryRequirements(this.buffer), properties);
    errdefer device.vk.freeMemory(this.memory_region);
    try device.vk.device.bindBufferMemory(this.buffer, this.memory_region.memory, this.memory_region.offset);

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Buffer, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyBuffer(this.vk.buffer, vk_alloc);
    device.vk.freeMemory(this.vk.memory_region);
    alloc.destroy(this.vk);
}

pub fn size(this: gpu.Buffer, _: gpu.Device) gpu.Size {
    return this.vk.size_;
}

pub const Region = struct {
    pub fn map(this: gpu.Buffer.Region, device: gpu.Device) ![]u8 {
        const size_ = switch (this.size_or_whole) {
            .size => |x| x,
            .whole => vk.WHOLE_SIZE,
        };

        const data = (try device.vk.device.mapMemory(this.buffer.vk.memory_region.memory, this.offset, size_, .{})).?;
        const many_ptr: [*]u8 = @ptrCast(data);
        return many_ptr[0..size_];
    }

    pub fn unmap(this: gpu.Buffer.Region, device: gpu.Device) void {
        device.vk.device.unmapMemory(this.buffer.vk.memory_region.memory);
    }
};
