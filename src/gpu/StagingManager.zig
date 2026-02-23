const std = @import("std");
const gpu = @import("../gpu.zig");

const StagingManager = @This();

per_frame_in_flight: []PerFrameInFlight,
frame_index: usize,
buffer_size: gpu.Size,

const PerFrameInFlight = struct {
    buffer: gpu.Buffer,
    mapping: []u8,
    offset: gpu.Size,

    fn init(pf: *PerFrameInFlight, info: InitInfo) !void {
        const buffer = try info.device.initBuffer(.{
            .alloc = info.alloc,
            .loc = .host,
            .usage = .{ .src = true },
            .size = info.buffer_size,
        });
        errdefer buffer.deinit(info.device, info.alloc);

        const mapping = try buffer.map(info.device);
        errdefer buffer.unmap(info.device);

        pf.* = .{
            .buffer = buffer,
            .mapping = mapping,
            .offset = 0,
        };
    }

    fn deinit(pf: *PerFrameInFlight, device: gpu.Device, alloc: std.mem.Allocator) void {
        pf.buffer.unmap(device);
        pf.buffer.deinit(device, alloc);
    }
};

pub const InitInfo = struct {
    alloc: std.mem.Allocator,
    device: gpu.Device,
    buffer_size: gpu.Size,
    frames_in_flight: usize,
};

pub fn init(info: InitInfo) !StagingManager {
    const per_frame_in_flight = try info.alloc.alloc(PerFrameInFlight, info.frames_in_flight);
    errdefer info.alloc.free(per_frame_in_flight);

    var init_count: usize = 0;
    errdefer for (per_frame_in_flight[0..init_count]) |*pf| pf.deinit(info.device, info.alloc);
    for (per_frame_in_flight) |*per_frame| {
        try per_frame.init(info);
        init_count += 1;
    }

    return .{
        .per_frame_in_flight = per_frame_in_flight,
        .frame_index = 0,
        .buffer_size = info.buffer_size,
    };
}

pub fn deinit(man: *StagingManager, device: gpu.Device, alloc: std.mem.Allocator) void {
    for (man.per_frame_in_flight) |*pf| {
        pf.deinit(device, alloc);
    }
    alloc.free(man.per_frame_in_flight);
}

pub fn reset(man: *StagingManager) void {
    const per_frame = &man.per_frame_in_flight[man.frame_index];
    per_frame.offset = 0;
}

pub fn nextFrame(man: *StagingManager) void {
    man.frame_index = (man.frame_index + 1) % man.per_frame_in_flight.len;
    man.reset();
}

pub const AllocationBytes = struct {
    slice: []u8,
    region: gpu.Buffer.Region,
};

pub fn allocateBytesAligned(man: *StagingManager, size: gpu.Size, alignment: std.mem.Alignment) !AllocationBytes {
    const per_frame = &man.per_frame_in_flight[man.frame_index];
    const offset = std.mem.alignForward(gpu.Size, per_frame.offset, alignment.toByteUnits());
    const end = offset + size;
    per_frame.offset = end;

    if (end > man.buffer_size) return error.StagingFull;

    return .{
        .slice = per_frame.mapping[offset..end],
        .region = .{
            .buffer = per_frame.buffer,
            .offset = offset,
            .size_or_whole = .{ .size = size },
        },
    };
}

pub fn AllocationTyped(T: type, alignment: usize) type {
    return struct {
        slice: []align(alignment) T,
        region: gpu.Buffer.Region,
    };
}

pub fn allocateAligned(man: *StagingManager, T: type, n: gpu.Size, alignment: std.mem.Alignment) !AllocationTyped(T, 1) {
    const bytes = try man.allocateBytesAligned(n * @sizeOf(T), alignment);
    const many_ptr_t: [*]align(1) T = @ptrCast(bytes.slice.ptr);

    return .{
        .slice = many_ptr_t[0..n],
        .region = bytes.region,
    };
}

pub fn allocate(man: *StagingManager, T: type, n: gpu.Size) !AllocationTyped(T, @alignOf(T)) {
    const result = try man.allocateAligned(T, n, .fromByteUnits(@alignOf(T)));

    return .{
        .slice = @alignCast(result.slice),
        .region = result.region,
    };
}
