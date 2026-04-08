const std = @import("std");
const gpu = @import("gpu.zig");

const PushAlloc = @This();

buffer: gpu.Buffer,
frames_in_flight: u32,
frame_index: u32 = 0,
size_pf: gpu.Size,
offset: gpu.Size = 0,

pub fn reset(alloc: *PushAlloc) void {
    alloc.offset = 0;
}

pub fn nextFrame(alloc: *PushAlloc) void {
    alloc.frame_index = (alloc.frame_index + 1) % alloc.frames_in_flight;
    alloc.offset = 0;
}

pub fn allocTAligned(alloc: *PushAlloc, T: type, count: usize, alignment: std.mem.Alignment) !gpu.Buffer.Region {
    const size = @sizeOf(T) * count;
    const aligned_offset = std.mem.alignForward(gpu.Size, alloc.offset, alignment.toByteUnits());
    if (aligned_offset + size > alloc.size_pf) return error.BufferFull;
    alloc.offset = aligned_offset + size;

    return .{
        .buffer = alloc.buffer,
        .offset = alloc.frameOffset() + aligned_offset,
        .size = size,
    };
}

pub fn allocT(alloc: *PushAlloc, T: type, count: usize) !gpu.Buffer.Region {
    return alloc.allocTAligned(T, count, @alignOf(T));
}

pub inline fn perFrameRegion(alloc: PushAlloc) gpu.Buffer.Region {
    return .{
        .buffer = alloc.buffer,
        .offset = alloc.frameOffset(),
        .size = alloc.size_pf,
    };
}

pub inline fn usedRegion(alloc: PushAlloc) gpu.Buffer.Region {
    return .{
        .buffer = alloc.buffer,
        .offset = alloc.frameOffset(),
        .size = alloc.offset,
    };
}

pub inline fn frameOffset(alloc: PushAlloc) gpu.Size {
    return @as(gpu.Size, alloc.frame_index) * alloc.size_pf;
}
