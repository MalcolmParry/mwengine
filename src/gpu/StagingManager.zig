const std = @import("std");
const gpu = @import("../gpu.zig");

const StagingManager = @This();

buffer: gpu.Buffer,
mapping: []u8,
size: gpu.Size,
offset: std.atomic.Value(gpu.Size),
max_alignment: usize,

pub const InitInfo = struct {
    alloc: std.mem.Allocator,
    device: gpu.Device,
    buffer_size: gpu.Size,
    max_alignment: std.mem.Alignment,
};

pub fn init(info: InitInfo) !StagingManager {
    const buffer = try info.device.initBuffer(.{
        .alloc = info.alloc,
        .loc = .host,
        .usage = .{ .src = true },
        .size = info.buffer_size,
    });
    errdefer buffer.deinit(info.device, info.alloc);

    const mapping = try buffer.map(info.device);
    errdefer buffer.unmap(info.device);

    return .{
        .buffer = buffer,
        .mapping = mapping,
        .size = info.buffer_size,
        .offset = .init(0),
        .max_alignment = info.max_alignment.toByteUnits(),
    };
}

pub fn deinit(man: *StagingManager, device: gpu.Device, alloc: std.mem.Allocator) void {
    man.buffer.unmap(device);
    man.buffer.deinit(device, alloc);
}

/// externally synchronized
pub fn reset(man: *StagingManager) void {
    man.offset.store(0, .monotonic);
}

pub const Allocation = struct {
    slice: []u8,
    region: gpu.Buffer.Region,
};

/// thread safe
pub fn allocate(man: *StagingManager, size: gpu.Size) !Allocation {
    const aligned_size = std.mem.alignForward(gpu.Size, size, man.max_alignment);
    const offset = man.offset.fetchAdd(aligned_size, .monotonic);
    const end = offset + size;

    if (end > man.size) return error.StagingFull;

    return .{
        .slice = man.mapping[offset..end],
        .region = .{
            .buffer = man.buffer,
            .offset = offset,
            .size_or_whole = .{ .size = size },
        },
    };
}

pub fn AllocationTyped(T: type) type {
    return struct {
        slice: []T,
        region: gpu.Buffer.Region,
    };
}

/// thread safe
pub fn allocateT(man: *StagingManager, T: type, n: gpu.Size) !AllocationTyped(T) {
    std.debug.assert(@alignOf(T) <= man.max_alignment);

    const bytes = try man.allocate(n * @sizeOf(T));
    const many_ptr_t: [*]T = @ptrCast(@alignCast(bytes.slice.ptr));

    return .{
        .slice = many_ptr_t[0..n],
        .region = bytes.region,
    };
}
