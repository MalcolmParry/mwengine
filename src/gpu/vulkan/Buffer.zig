const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const MemoryRegion = @import("Device.zig").MemoryRegion;

const Buffer = @This();

pub const Location = enum {
    host,
    device,
};

pub const Usage = packed struct {
    const BackingInt = @typeInfo(@TypeOf(@This())).@"struct".backing_integer.?;
    const all: Usage = @bitCast(std.math.maxInt(BackingInt));

    src: bool = false,
    dst: bool = false,
    vertex: bool = false,
    index: bool = false,
    uniform: bool = false,
};

pub const CreateInfo = struct {
    loc: Location,
    usage: Usage,
    size: gpu.Size,
};

_buffer: vk.Buffer,
_memory_region: MemoryRegion,
size: gpu.Size,

pub fn init(device: gpu.Device, info: CreateInfo) !@This() {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const vk_usage: vk.BufferUsageFlags = .{
        .vertex_buffer_bit = info.usage.vertex,
        .index_buffer_bit = info.usage.index,
        .uniform_buffer_bit = info.usage.uniform,
        .transfer_src_bit = info.usage.src,
        .transfer_dst_bit = info.usage.dst,
    };

    const buffer = try device.vk.device.createBuffer(&.{
        .size = info.size,
        .usage = vk_usage,
        .sharing_mode = .exclusive,
    }, vk_alloc);
    errdefer device.vk.device.destroyBuffer(buffer, vk_alloc);

    const properties: vk.MemoryPropertyFlags = switch (info.loc) {
        .host => .{ .host_visible_bit = true },
        .device => .{ .device_local_bit = true },
    };

    const mem_region = try device.vk.allocateMemory(device.vk.device.getBufferMemoryRequirements(buffer), properties);
    errdefer device.vk.freeMemory(mem_region);
    try device.vk.device.bindBufferMemory(buffer, mem_region.memory, mem_region.offset);

    return .{
        ._buffer = buffer,
        ._memory_region = mem_region,
        .size = info.size,
    };
}

pub fn deinit(this: *@This(), device: gpu.Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyBuffer(this._buffer, vk_alloc);
    device.vk.freeMemory(this._memory_region);
}

pub fn map(this: *@This(), device: gpu.Device) ![]u8 {
    return this.region().map(device);
}

pub fn unmap(this: *@This(), device: gpu.Device) void {
    this.region().unmap(device);
}

pub fn region(this: *@This()) Region {
    return .{
        .buffer = this,
        .offset = 0,
        .size = this.size,
    };
}

pub const Region = struct {
    buffer: *Buffer,
    offset: gpu.Size,
    size: gpu.Size,

    pub fn map(this: @This(), device: gpu.Device) ![]u8 {
        const data = (try device.vk.device.mapMemory(this.buffer._memory_region.memory, this.offset, this.size, .{})).?;
        const many_ptr: [*]u8 = @ptrCast(data);
        return many_ptr[0..this.size];
    }

    pub fn unmap(this: @This(), device: gpu.Device) void {
        device.vk.device.unmapMemory(this.buffer._memory_region.memory);
    }
};
