const std = @import("std");
const gpu = @import("gpu.zig");

pub fn FrameRingPool(comptime T: type, comptime createFn: anytype, comptime CreateArgs: type) type {
    return struct {
        const This = @This();

        free_list: std.ArrayList(T),
        in_use_lists: []std.ArrayList(T),
        frame_index: u32,
        total_items: u32,

        pub fn init(alloc: std.mem.Allocator, frames_in_flight: usize) !This {
            const in_use_lists = try alloc.alloc(std.ArrayList(T), frames_in_flight);
            errdefer alloc.free(in_use_lists);
            @memset(in_use_lists, .empty);

            return .{
                .free_list = .empty,
                .in_use_lists = in_use_lists,
                .frame_index = 0,
                .total_items = 0,
            };
        }

        /// doesnt deinit objects
        pub fn deinit(pool: *This, alloc: std.mem.Allocator) void {
            pool.free_list.deinit(alloc);
            for (pool.in_use_lists) |*x| x.deinit(alloc);
            alloc.free(pool.in_use_lists);
        }

        pub fn nextFrame(pool: *This) void {
            const frames_in_flight: u32 = @intCast(pool.in_use_lists.len);
            pool.frame_index = (pool.frame_index + 1) % frames_in_flight;
            const list = &pool.in_use_lists[pool.frame_index];

            pool.free_list.appendSliceAssumeCapacity(list.items);
            list.clearRetainingCapacity();
        }

        pub fn allocate(pool: *This, alloc: std.mem.Allocator, args: CreateArgs) !T {
            try pool.ensureFree(alloc, args, 1);
            return pool.allocateAssumeCapacity();
        }

        pub fn allocateBounded(pool: *This) !T {
            if (pool.free_list.items.len == 0) return error.OutOfPoolMemory;
            return pool.allocateAssumeCapacity();
        }

        pub fn allocateAssumeCapacity(pool: *This) T {
            const result = pool.free_list.pop() orelse unreachable;
            pool.in_use_lists[pool.frame_index].appendAssumeCapacity(result);
            return result;
        }

        pub fn ensureFree(pool: *This, alloc: std.mem.Allocator, args: CreateArgs, count: usize) !void {
            if (pool.free_list.items.len >= count) return;

            try pool.reserve(alloc, args, count - pool.free_list.items.len);
        }

        pub fn reserve(pool: *This, alloc: std.mem.Allocator, args: CreateArgs, count: usize) !void {
            try pool.free_list.ensureUnusedCapacity(alloc, count);
            for (0..count) |_| {
                const obj_and_error = @call(.auto, createFn, args);
                const obj = if (@typeInfo(@TypeOf(obj_and_error)) == .error_union) try obj_and_error else obj_and_error;
                pool.free_list.appendAssumeCapacity(obj);
            }

            pool.total_items += @intCast(count);
            for (pool.in_use_lists) |*x| try x.ensureTotalCapacity(alloc, pool.total_items);
            try pool.free_list.ensureTotalCapacity(alloc, pool.total_items);
        }
    };
}
