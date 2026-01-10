const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const Buffer = @import("Buffer.zig");
const Shader = @import("Shader.zig");

_descriptor_pool: vk.DescriptorPool,
_descriptor_set: vk.DescriptorSet,

pub fn init(device: gpu.Device, layout: *Layout) !@This() {
    const vk_alloc: ?*vk.AllocationCallbacks = null;

    const descriptor_pool = try device.vk.device.createDescriptorPool(&.{
        .pool_size_count = @intCast(layout._sizes.len),
        .p_pool_sizes = layout._sizes.ptr,
        .max_sets = 1,
    }, vk_alloc);
    errdefer device.vk.device.destroyDescriptorPool(descriptor_pool, vk_alloc);

    var descriptor_set: vk.DescriptorSet = undefined;
    try device.vk.device.allocateDescriptorSets(&.{
        .descriptor_pool = descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&layout._layout),
    }, @ptrCast(&descriptor_set));

    return .{
        ._descriptor_pool = descriptor_pool,
        ._descriptor_set = descriptor_set,
    };
}

pub fn deinit(this: *@This(), device: gpu.Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyDescriptorPool(this._descriptor_pool, vk_alloc);
}

const Write = struct {
    binding: u32,
    data: union(Type) {
        uniform: []const Buffer.Region,
    },
};

pub fn update(this: *@This(), device: gpu.Device, writes: []const Write, alloc: std.mem.Allocator) !void {
    const descriptor_writes = try alloc.alloc(vk.WriteDescriptorSet, writes.len);
    defer alloc.free(descriptor_writes);

    var all_buffer_infos: std.ArrayList(vk.DescriptorBufferInfo) = try .initCapacity(alloc, writes.len);
    defer all_buffer_infos.deinit(alloc);

    for (writes, descriptor_writes) |write, *descriptor_write| {
        var count: usize = undefined;
        var buffer_infos: ?[*]vk.DescriptorBufferInfo = null;

        switch (write.data) {
            .uniform => |buffer_regions| {
                count = buffer_regions.len;
                const buffer_infos_start = all_buffer_infos.items.len;

                for (buffer_regions) |buffer_region| {
                    all_buffer_infos.appendAssumeCapacity(.{
                        .buffer = buffer_region.buffer._buffer,
                        .offset = buffer_region.offset,
                        .range = buffer_region.size,
                    });
                }

                buffer_infos = @ptrCast(&all_buffer_infos.items[buffer_infos_start]);
            },
        }

        descriptor_write.* = .{
            .dst_set = this._descriptor_set,
            .dst_binding = write.binding,
            .dst_array_element = 0,
            .descriptor_type = switch (write.data) {
                .uniform => .uniform_buffer,
            },
            .descriptor_count = @intCast(count),
            .p_buffer_info = buffer_infos.?,
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        };
    }

    device.vk.device.updateDescriptorSets(
        @intCast(writes.len),
        descriptor_writes.ptr,
        0,
        null,
    );
}

pub fn _nativesFromSlice(these: []const @This(), alloc: std.mem.Allocator) ![]const vk.DescriptorSet {
    const natives = try alloc.alloc(vk.DescriptorSet, these.len);
    errdefer alloc.free(natives);

    for (these, natives) |*this, *native| {
        native.* = this._descriptor_set;
    }

    return natives;
}

pub const Type = enum {
    uniform,
    // image,
};

pub const Layout = struct {
    _layout: vk.DescriptorSetLayout,
    _sizes: []vk.DescriptorPoolSize,

    pub const Descriptor = struct {
        t: Type,
        stage: Shader.StageFlags,
        binding: u32,
        count: u32,
    };

    pub const CreateInfo = struct {
        alloc: std.mem.Allocator,
        descriptors: []const Descriptor,
    };

    pub fn init(device: gpu.Device, info: CreateInfo) !@This() {
        const bindings = try info.alloc.alloc(vk.DescriptorSetLayoutBinding, info.descriptors.len);
        defer info.alloc.free(bindings);

        const sizes = try info.alloc.alloc(vk.DescriptorPoolSize, info.descriptors.len);
        errdefer info.alloc.free(sizes);

        for (bindings, sizes, info.descriptors, 0..) |*binding, *size, descriptor, i| {
            const t: vk.DescriptorType = switch (descriptor.t) {
                .uniform => .uniform_buffer,
                // .image => .combined_image_sampler,
            };

            binding.* = .{
                .binding = @intCast(i),
                .descriptor_type = t,
                .descriptor_count = descriptor.count,
                .stage_flags = .{
                    .vertex_bit = descriptor.stage.vertex,
                    .fragment_bit = descriptor.stage.pixel,
                },
            };

            size.* = .{
                .type = t,
                .descriptor_count = descriptor.count,
            };
        }

        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const layout = try device.vk.device.createDescriptorSetLayout(&.{
            .binding_count = @intCast(bindings.len),
            .p_bindings = @ptrCast(bindings.ptr),
        }, vk_alloc);

        return .{
            ._layout = layout,
            ._sizes = sizes,
        };
    }

    pub fn deinit(this: @This(), device: gpu.Device, alloc: std.mem.Allocator) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroyDescriptorSetLayout(this._layout, vk_alloc);
        alloc.free(this._sizes);
    }

    pub fn _nativesFromSlice(these: []const @This(), alloc: std.mem.Allocator) ![]const vk.DescriptorSetLayout {
        const natives = try alloc.alloc(vk.DescriptorSetLayout, these.len);
        errdefer alloc.free(natives);

        for (these, natives) |*this, *native| {
            native.* = this._layout;
        }

        return natives;
    }
};
