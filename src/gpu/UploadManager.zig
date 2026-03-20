const std = @import("std");
const gpu = @import("../gpu.zig");

const UploadManager = @This();

alloc: std.mem.Allocator,
stage_man: *gpu.StagingManager,
copies: std.MultiArrayList(Copy) = .empty,
pre_copy_image_barriers: std.ArrayList(gpu.ImageBarrier) = .empty,
pre_copy_buffer_barriers: std.ArrayList(gpu.BufferBarrier) = .empty,
post_copy_image_barriers: std.ArrayList(gpu.ImageBarrier) = .empty,
post_copy_buffer_barriers: std.ArrayList(gpu.BufferBarrier) = .empty,

pub const Copy = struct {
    src: gpu.Buffer.Region,
    dst: gpu.Buffer.Region,
};

pub fn deinit(man: *UploadManager) void {
    man.post_copy_image_barriers.deinit(man.alloc);
    man.post_copy_buffer_barriers.deinit(man.alloc);
    man.pre_copy_image_barriers.deinit(man.alloc);
    man.pre_copy_buffer_barriers.deinit(man.alloc);
    man.copies.deinit(man.alloc);
}

pub fn upload(man: *UploadManager, cmd_encoder: gpu.CommandEncoder) !void {
    if (man.pre_copy_buffer_barriers.items.len > 0)
        cmd_encoder.cmdMemoryBarrier(.{
            .image_barriers = man.pre_copy_image_barriers.items,
            .buffer_barriers = man.pre_copy_buffer_barriers.items,
        });

    for (man.copies.items(.src), man.copies.items(.dst)) |src, dst| {
        cmd_encoder.cmdCopyBuffer(src, dst);
    }

    if (man.post_copy_buffer_barriers.items.len > 0)
        cmd_encoder.cmdMemoryBarrier(.{
            .image_barriers = man.post_copy_image_barriers.items,
            .buffer_barriers = man.post_copy_buffer_barriers.items,
        });

    man.copies.clearRetainingCapacity();
    man.pre_copy_image_barriers.clearRetainingCapacity();
    man.pre_copy_buffer_barriers.clearRetainingCapacity();
    man.post_copy_image_barriers.clearRetainingCapacity();
    man.post_copy_buffer_barriers.clearRetainingCapacity();
}

pub fn SubmitInfo(T: type) type {
    return struct {
        data: []const T,
        region: gpu.Buffer.Region,
        pre_copy_barrier: ?gpu.BufferBarrier = null,
        post_copy_barrier: ?gpu.BufferBarrier = null,
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

    if (info.pre_copy_barrier) |x|
        try man.pre_copy_buffer_barriers.append(man.alloc, x);

    if (info.post_copy_barrier) |x|
        try man.post_copy_buffer_barriers.append(man.alloc, x);
}
