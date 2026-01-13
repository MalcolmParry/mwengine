const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const Buffer = @import("Buffer.zig");
const Shader = @import("Shader.zig");

const ResourceSet = @This();
pub const Handle = *ResourceSet;

descriptor_pool: vk.DescriptorPool,
descriptor_set: vk.DescriptorSet,

pub fn init(device: gpu.Device, layout: gpu.ResourceSet.Layout, alloc: std.mem.Allocator) !gpu.ResourceSet {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const this = try alloc.create(ResourceSet);
    errdefer alloc.destroy(this);

    this.descriptor_pool = try device.vk.device.createDescriptorPool(&.{
        .pool_size_count = @intCast(layout.vk.sizes.len),
        .p_pool_sizes = layout.vk.sizes.ptr,
        .max_sets = 1,
    }, vk_alloc);
    errdefer device.vk.device.destroyDescriptorPool(this.descriptor_pool, vk_alloc);

    try device.vk.device.allocateDescriptorSets(&.{
        .descriptor_pool = this.descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&layout.vk.layout),
    }, @ptrCast(&this.descriptor_set));

    return .{ .vk = this };
}

pub fn deinit(this: gpu.ResourceSet, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyDescriptorPool(this.vk.descriptor_pool, vk_alloc);
    alloc.destroy(this.vk);
}

pub fn update(this: gpu.ResourceSet, device: gpu.Device, writes: []const gpu.ResourceSet.Write, alloc: std.mem.Allocator) !void {
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
            .dst_set = this.vk.descriptor_set,
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

pub fn nativesFromSlice(these: []const gpu.ResourceSet, alloc: std.mem.Allocator) ![]const vk.DescriptorSet {
    const natives = try alloc.alloc(vk.DescriptorSet, these.len);
    errdefer alloc.free(natives);

    for (these, natives) |*this, *native| {
        native.* = this.vk.descriptor_set;
    }

    return natives;
}

pub const Layout = struct {
    layout: vk.DescriptorSetLayout,
    sizes: []vk.DescriptorPoolSize,

    pub const Handle = *Layout;

    pub fn init(device: gpu.Device, info: gpu.ResourceSet.Layout.CreateInfo) !gpu.ResourceSet.Layout {
        const this = try info.alloc.create(Layout);
        errdefer info.alloc.destroy(this);

        const bindings = try info.alloc.alloc(vk.DescriptorSetLayoutBinding, info.descriptors.len);
        defer info.alloc.free(bindings);

        this.sizes = try info.alloc.alloc(vk.DescriptorPoolSize, info.descriptors.len);
        errdefer info.alloc.free(this.sizes);

        for (bindings, this.sizes, info.descriptors, 0..) |*binding, *size, descriptor, i| {
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
        this.layout = try device.vk.device.createDescriptorSetLayout(&.{
            .binding_count = @intCast(bindings.len),
            .p_bindings = @ptrCast(bindings.ptr),
        }, vk_alloc);
        errdefer device.vk.device.destroyDescriptorSetLayout(this.layout, vk_alloc);

        return .{ .vk = this };
    }

    pub fn deinit(this: gpu.ResourceSet.Layout, device: gpu.Device, alloc: std.mem.Allocator) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroyDescriptorSetLayout(this.vk.layout, vk_alloc);
        alloc.free(this.vk.sizes);
        alloc.destroy(this.vk);
    }

    pub fn nativesFromSlice(these: []const gpu.ResourceSet.Layout, alloc: std.mem.Allocator) ![]const vk.DescriptorSetLayout {
        const natives = try alloc.alloc(vk.DescriptorSetLayout, these.len);
        errdefer alloc.free(natives);

        for (these, natives) |*this, *native| {
            native.* = this.vk.layout;
        }

        return natives;
    }
};
