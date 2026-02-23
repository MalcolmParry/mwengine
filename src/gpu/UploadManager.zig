const std = @import("std");
const gpu = @import("../gpu.zig");

const UploadManager = @This();

alloc: std.mem.Allocator,
stage_man: *gpu.StagingManager,
copies: std.MultiArrayList(Copy) = .empty,
pre_copy_barriers: std.ArrayList(gpu.MemoryBarrier) = .empty,
post_copy_barriers: std.ArrayList(gpu.MemoryBarrier) = .empty,

pub const Copy = struct {
    src: gpu.Buffer.Region,
    dst: gpu.Buffer.Region,
};

pub fn deinit(man: *UploadManager) void {
    man.post_copy_barriers.deinit(man.alloc);
    man.pre_copy_barriers.deinit(man.alloc);
    man.copies.deinit(man.alloc);
}

pub fn upload(man: *UploadManager, device: gpu.Device, cmd_encoder: gpu.CommandEncoder) !void {
    if (man.pre_copy_barriers.items.len > 0)
        try cmd_encoder.cmdMemoryBarrier(device, man.pre_copy_barriers.items, man.alloc);

    for (man.copies.items(.src), man.copies.items(.dst)) |src, dst| {
        cmd_encoder.cmdCopyBuffer(device, src, dst);
    }

    if (man.post_copy_barriers.items.len > 0)
        try cmd_encoder.cmdMemoryBarrier(device, man.post_copy_barriers.items, man.alloc);

    man.copies.clearRetainingCapacity();
    man.pre_copy_barriers.clearRetainingCapacity();
    man.post_copy_barriers.clearRetainingCapacity();
}

pub fn SubmitInfo(T: type) type {
    return struct {
        data: []const T,
        region: gpu.Buffer.Region,
        pre_copy_barrier: ?gpu.MemoryBarrier = null,
        post_copy_barrier: ?gpu.MemoryBarrier = null,
    };
}

pub fn submit(man: *UploadManager, T: type, info: SubmitInfo(T)) !void {
    if (info.region.size_or_whole == .size)
        std.debug.assert(info.data.len * @sizeOf(T) == info.region.size_or_whole.size);

    const staging = try man.stage_man.allocate(T, info.data.len);
    @memcpy(staging.slice, info.data);

    try man.copies.append(man.alloc, .{
        .src = staging.region,
        .dst = info.region,
    });

    if (info.pre_copy_barrier) |x| {
        std.debug.assert(x == .buffer);
        try man.pre_copy_barriers.append(man.alloc, x);
    }

    if (info.post_copy_barrier) |x| {
        std.debug.assert(x == .buffer);
        try man.post_copy_barriers.append(man.alloc, x);
    }
}
