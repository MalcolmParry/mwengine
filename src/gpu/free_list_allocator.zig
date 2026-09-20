const std = @import("std");
const gpu = @import("gpu.zig");

const Options = struct {
    super_slab_size: comptime_int = 1024 * 1024 * 64,
    slab_size: comptime_int = 1024 * 256,
    allow_multiple_super_slabs: bool = true,
    stats: bool = false,
};

pub fn FreeListAllocator(comptime opts: Options) type {
    return struct {
        gpa: std.mem.Allocator,
        super_descs: std.ArrayList(SuperDesc) = .empty,

        slab_bump: u32 = slabs_per_super,
        first_free_slab: ?SuperAndSlab = null,

        first_slab_with_free_slot: [size_class_count]?SuperAndSlab = @splat(null),

        buffer_loc: gpu.MemLocation,
        buffer_usage: gpu.Buffer.Usage,
        stats: if (opts.stats) Stats else void = if (opts.stats) .{} else {},

        const GpuAlloc = @This();
        const super_size = opts.super_slab_size;
        const slab_size = opts.slab_size;
        const slabs_per_super = opts.super_slab_size / opts.slab_size;

        const max_alloc = slab_size / 2;
        const min_alloc = 8;
        const log2_min_alloc = std.math.log2(min_alloc);
        const max_size_class = sizeClass(max_alloc);
        const size_class_count = max_size_class + 1;

        comptime {
            std.debug.assert(slabs_per_super >= 2);
        }

        pub const Stats = struct {
            slabs_used: [size_class_count]u32 = @splat(0),
            wasted_space: [size_class_count]u64 = @splat(0),
            allocs: [size_class_count]u32 = @splat(0),
        };

        const SuperDesc = struct {
            buffer: gpu.Buffer,
            slab_descs: [slabs_per_super]SlabDescOrFree,
        };

        const SlabDescOrFree = union(enum) {
            desc: SlabDesc,
            free: ?SuperAndSlab,
        };

        const SlotIndex = std.math.IntFittingRange(0, classSlots(sizeClass(min_alloc)) + 1);
        const OptSlotIndex = enum(SlotIndex) {
            none = std.math.maxInt(SlotIndex),
            _,

            fn wrap(x: ?SlotIndex) OptSlotIndex {
                return if (x) |y| @enumFromInt(y) else .none;
            }

            fn unwrap(x: OptSlotIndex) ?SlotIndex {
                if (x == .none) return null;
                return @intFromEnum(x);
            }
        };

        const SlabDesc = struct {
            free_count: u32,
            prev_slab_with_free_slot: ?SuperAndSlab = null,
            next_slab_with_free_slot: ?SuperAndSlab = null,
            bump: SlotIndex,
            first_free: ?SlotIndex,
            free_list: []OptSlotIndex,
        };

        const SuperAndSlab = struct {
            super: u32,
            slab: u32,
        };

        pub fn deinit(gpu_alloc: *GpuAlloc, device: gpu.Device) void {
            const gpa = gpu_alloc.gpa;
            for (gpu_alloc.super_descs.items) |super| {
                super.buffer.deinit(device, gpa);
                for (super.slab_descs[0..]) |slab| {
                    switch (slab) {
                        .desc => |desc| gpa.free(desc.free_list),
                        .free => {},
                    }
                }
            }

            gpu_alloc.super_descs.deinit(gpa);
        }

        fn allocSlab(gpu_alloc: *GpuAlloc, device: gpu.Device) !SuperAndSlab {
            if (gpu_alloc.slab_bump < slabs_per_super) {
                const super: u32 = @intCast(gpu_alloc.super_descs.items.len - 1);
                const slab = gpu_alloc.slab_bump;
                gpu_alloc.slab_bump += 1;

                return .{
                    .super = super,
                    .slab = slab,
                };
            }

            if (gpu_alloc.first_free_slab) |slot| {
                const desc = &gpu_alloc.super_descs.items[slot.super].slab_descs[slot.slab];
                gpu_alloc.first_free_slab = desc.free;
                return slot;
            }

            if (!opts.allow_multiple_super_slabs and gpu_alloc.super_descs.items.len != 0) return error.SuperSlabFull;

            const gpa = gpu_alloc.gpa;
            const buffer = try device.initBuffer(.{
                .alloc = gpa,
                .size = super_size,
                .loc = gpu_alloc.buffer_loc,
                .usage = gpu_alloc.buffer_usage,
            });
            errdefer buffer.deinit(device, gpa);
            buffer.debugLabel(device, "free list allocator super slab buffer");

            try gpu_alloc.super_descs.append(gpa, .{
                .slab_descs = undefined,
                .buffer = buffer,
            });
            errdefer gpu_alloc.super_descs.items.len -= 1;
            @memset(gpu_alloc.super_descs.items[gpu_alloc.super_descs.items.len - 1].slab_descs[0..], .{ .free = null });

            gpu_alloc.slab_bump = 1;
            return .{
                .super = @intCast(gpu_alloc.super_descs.items.len - 1),
                .slab = 0,
            };
        }

        fn freeSlab(gpu_alloc: *GpuAlloc, slot: SuperAndSlab) void {
            const desc = &gpu_alloc.super_descs.items[slot.super].slab_descs[slot.slab];
            desc.free = gpu_alloc.first_free_slab;
            gpu_alloc.first_free_slab = slot;
        }

        pub const Alloc = struct {
            super_slab: u32,
            offset: u32,
            size: u32,
        };

        pub fn alloc(gpu_alloc: *GpuAlloc, device: gpu.Device, size: u32) !Alloc {
            const class = sizeClass(size);
            const slot_count = classSlots(class);
            const slot_size = classSize(class);

            const slab = gpu_alloc.first_slab_with_free_slot[class] orelse blk: {
                const new = try allocSlab(gpu_alloc, device);
                errdefer freeSlab(gpu_alloc, new);
                const free_list = try gpu_alloc.gpa.alloc(OptSlotIndex, slot_count);
                gpu_alloc.super_descs.items[new.super].slab_descs[new.slab] = .{ .desc = .{
                    .free_count = slot_count,
                    .bump = 0,
                    .first_free = null,
                    .free_list = free_list,
                } };

                gpu_alloc.first_slab_with_free_slot[class] = new;
                if (opts.stats) gpu_alloc.stats.slabs_used[class] += 1;
                break :blk new;
            };

            if (opts.stats) {
                gpu_alloc.stats.allocs[class] += 1;
                gpu_alloc.stats.wasted_space[class] += slot_size - size;
            }

            const desc = &gpu_alloc.super_descs.items[slab.super].slab_descs[slab.slab].desc;
            desc.free_count -= 1;
            if (desc.free_count == 0) {
                if (desc.prev_slab_with_free_slot) |prev| {
                    gpu_alloc.super_descs.items[prev.super].slab_descs[prev.slab].desc.next_slab_with_free_slot = desc.next_slab_with_free_slot;
                } else {
                    gpu_alloc.first_slab_with_free_slot[class] = desc.next_slab_with_free_slot;
                }

                if (desc.next_slab_with_free_slot) |next| {
                    gpu_alloc.super_descs.items[next.super].slab_descs[next.slab].desc.prev_slab_with_free_slot = desc.prev_slab_with_free_slot;
                }
            }

            if (desc.bump < slot_count) {
                const slot = desc.bump;
                desc.bump += 1;

                return .{
                    .super_slab = slab.super,
                    .size = size,
                    .offset = (slab.slab * slab_size) + (slot * slot_size),
                };
            }

            const slot = desc.first_free orelse unreachable;
            desc.first_free = desc.free_list[slot].unwrap();

            return .{
                .super_slab = slab.super,
                .size = size,
                .offset = (slab.slab * slab_size) + (slot * slot_size),
            };
        }

        pub fn free(gpu_alloc: *GpuAlloc, allocation: Alloc) void {
            const class = sizeClass(allocation.size);
            const slot_size = classSize(class);
            const slot_count = classSlots(class);

            const super = allocation.super_slab;
            const slab = allocation.offset / slab_size;
            const slot_offset = allocation.offset % slab_size;
            const slot: SlotIndex = @intCast(slot_offset / slot_size);
            const super_and_slab: SuperAndSlab = .{ .super = super, .slab = slab };

            const desc = &gpu_alloc.super_descs.items[super].slab_descs[slab].desc;
            if (desc.free_count == 0) {
                if (gpu_alloc.first_slab_with_free_slot[class]) |other| {
                    gpu_alloc.super_descs.items[other.super].slab_descs[other.slab].desc.prev_slab_with_free_slot = super_and_slab;
                }

                desc.prev_slab_with_free_slot = null;
                desc.next_slab_with_free_slot = gpu_alloc.first_slab_with_free_slot[class];
                gpu_alloc.first_slab_with_free_slot[class] = super_and_slab;
            }

            desc.free_list[slot] = .wrap(desc.first_free);
            desc.first_free = slot;
            desc.free_count += 1;

            if (desc.free_count == slot_count) {
                if (desc.next_slab_with_free_slot) |next| {
                    gpu_alloc.super_descs.items[next.super].slab_descs[next.slab].desc.prev_slab_with_free_slot = desc.prev_slab_with_free_slot;
                }

                if (desc.prev_slab_with_free_slot) |prev| {
                    gpu_alloc.super_descs.items[prev.super].slab_descs[prev.slab].desc.next_slab_with_free_slot = desc.next_slab_with_free_slot;
                } else {
                    gpu_alloc.first_slab_with_free_slot[class] = desc.next_slab_with_free_slot;
                }

                gpu_alloc.gpa.free(desc.free_list);
                gpu_alloc.super_descs.items[super].slab_descs[slab] = .{ .free = gpu_alloc.first_free_slab };
                gpu_alloc.first_free_slab = super_and_slab;

                if (opts.stats) gpu_alloc.stats.slabs_used[class] -= 1;
            }

            if (opts.stats) {
                gpu_alloc.stats.allocs[class] -= 1;
                gpu_alloc.stats.wasted_space[class] -= slot_size - allocation.size;
            }
        }

        pub fn queryTotalUsed(gpu_alloc: *GpuAlloc) gpu.Size {
            comptime std.debug.assert(opts.stats);
            return gpu_alloc.super_descs.items.len * opts.super_slab_size;
        }

        pub fn querySlabsUsed(gpu_alloc: *GpuAlloc) gpu.Size {
            comptime std.debug.assert(opts.stats);
            var used: gpu.Size = 0;
            for (&gpu_alloc.stats.slabs_used) |x| used += x;
            return used;
        }

        pub fn queryUsed(gpu_alloc: *GpuAlloc) gpu.Size {
            comptime std.debug.assert(opts.stats);
            var used: gpu.Size = 0;
            for (&gpu_alloc.stats.allocs, 0..) |x, i| used += x * classSize(@intCast(i));
            return used;
        }

        pub fn queryWasted(gpu_alloc: *GpuAlloc) gpu.Size {
            comptime std.debug.assert(opts.stats);
            var wasted: gpu.Size = 0;
            for (&gpu_alloc.stats.wasted_space) |x| wasted += x;
            return wasted;
        }

        const SizeClass = std.math.Log2Int(u32);
        fn sizeClass(size: u32) SizeClass {
            std.debug.assert(size != 0);
            std.debug.assert(size <= max_alloc);

            const size_or_min: u32 = @max(size, min_alloc);
            const log2: SizeClass = @intCast(@bitSizeOf(u32) - @clz(size_or_min - 1));
            const half = @as(u32, 1) << (log2 - 1);
            const three_quarters = half + (half >> 1);
            const class = (log2 - log2_min_alloc) * 2;
            return if (size_or_min <= three_quarters) class - 1 else class;
        }

        fn classSize(class: SizeClass) u32 {
            std.debug.assert(class <= max_size_class);

            const has_half = class % 2 == 1;
            const log2 = class / 2 + log2_min_alloc;
            const power_of_2 = @as(u32, 1) << log2;
            const half = power_of_2 >> 1;
            return if (has_half) power_of_2 + half else power_of_2;
        }

        fn classSlots(class: SizeClass) u32 {
            return slab_size / classSize(class);
        }
    };
}

test "size classes" {
    const GpuAlloc = FreeListAllocator(.{});

    for (1..256) |i| {
        const class = GpuAlloc.sizeClass(i);
        const size = GpuAlloc.classSize(class);
        try std.testing.expect(size >= i);
        try std.testing.expect(class == GpuAlloc.sizeClass(size));
    }
}
