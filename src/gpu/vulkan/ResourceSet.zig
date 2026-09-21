const std = @import("std");
const gpu = @import("../gpu.zig");
const vk = @import("vulkan");
const Buffer = @import("Buffer.zig");
const Shader = @import("Shader.zig");
const Image = @import("Image.zig");

const ResourceSet = @This();
pub const Handle = ResourceSet;

descriptor_pool: vk.DescriptorPool,
descriptor_set: vk.DescriptorSet,

pub fn init(device: gpu.Device, layout: gpu.ResourceSet.Layout) gpu.ResourceSet.InitError!gpu.ResourceSet {
    const vk_alloc: ?*vk.AllocationCallbacks = null;

    const descriptor_pool = device.vk.device.createDescriptorPool(&.{
        .pool_size_count = @intCast(layout.vk.sizes.len),
        .p_pool_sizes = layout.vk.sizes.ptr,
        .max_sets = 1,
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.FragmentationEXT => error.Fragmentation,
        error.Unknown => error.Unknown,
    };
    errdefer device.vk.device.destroyDescriptorPool(descriptor_pool, vk_alloc);

    var descriptor_set: vk.DescriptorSet = .null_handle;
    device.vk.device.allocateDescriptorSets(&.{
        .descriptor_pool = descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&layout.vk.layout),
    }, (&descriptor_set)[0..1]) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.OutOfPoolMemory => error.OutOfPoolMemory,
        error.FragmentedPool => error.FragmentedPool,
        error.Unknown => error.Unknown,
    };

    return .{ .vk = .{
        .descriptor_pool = descriptor_pool,
        .descriptor_set = descriptor_set,
    } };
}

pub fn deinit(res_set: gpu.ResourceSet, device: gpu.Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyDescriptorPool(res_set.vk.descriptor_pool, vk_alloc);
}

pub fn update(res_set: gpu.ResourceSet, device: gpu.Device, writes: []const gpu.ResourceSet.Write) !void {
    var arena_obj = device.vk.arena.promote(device.vk.gpa);
    defer {
        _ = arena_obj.reset(.retain_capacity);
        device.vk.arena = arena_obj.state;
    }
    const arena = arena_obj.allocator();

    var buffer_info_count: usize = 0;
    var image_info_count: usize = 0;
    for (writes) |write| {
        switch (write.data) {
            .uniform => |regions| buffer_info_count += regions.len,
            .image => |images| image_info_count += images.len,
            .storage => |regions| buffer_info_count += regions.len,
        }
    }

    const descriptor_writes = try arena.alloc(vk.WriteDescriptorSet, writes.len);
    var all_buffer_infos: std.ArrayList(vk.DescriptorBufferInfo) = try .initCapacity(arena, buffer_info_count);
    var all_image_infos: std.ArrayList(vk.DescriptorImageInfo) = try .initCapacity(arena, image_info_count);

    for (writes, descriptor_writes) |write, *descriptor_write| {
        var count: usize = undefined;
        var buffer_infos: [*]vk.DescriptorBufferInfo = undefined;
        var image_infos: [*]vk.DescriptorImageInfo = undefined;

        switch (write.data) {
            .uniform, .storage => |regions| {
                count = regions.len;
                buffer_infos = all_buffer_infos.items.ptr + all_buffer_infos.items.len;

                for (regions) |region| {
                    all_buffer_infos.appendAssumeCapacity(.{
                        .buffer = region.buffer.impl.vk.buffer,
                        .offset = region.offset,
                        .range = region.size,
                    });
                }
            },
            .image => |images| {
                count = images.len;
                image_infos = all_image_infos.items.ptr + all_image_infos.items.len;

                for (images) |image| {
                    all_image_infos.appendAssumeCapacity(.{
                        .image_layout = Image.layoutToNative(image.layout),
                        .image_view = image.view.vk.image_view,
                        .sampler = image.sampler.vk.sampler,
                    });
                }
            },
        }

        descriptor_write.* = .{
            .dst_set = res_set.vk.descriptor_set,
            .dst_binding = write.binding,
            .dst_array_element = 0,
            .descriptor_type = switch (write.data) {
                .uniform => .uniform_buffer,
                .image => .combined_image_sampler,
                .storage => .storage_buffer,
            },
            .descriptor_count = @intCast(count),
            .p_buffer_info = buffer_infos,
            .p_image_info = image_infos,
            .p_texel_buffer_view = undefined,
        };
    }

    device.vk.device.updateDescriptorSets(
        descriptor_writes,
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

    pub const Handle = Layout;

    pub fn init(device: gpu.Device, descriptors: []const gpu.ResourceSet.Layout.Descriptor) gpu.ResourceSet.Layout.InitError!gpu.ResourceSet.Layout {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const gpa = device.vk.gpa;

        const bindings = try gpa.alloc(vk.DescriptorSetLayoutBinding, descriptors.len);
        defer gpa.free(bindings);

        const binding_flags = try gpa.alloc(vk.DescriptorBindingFlags, descriptors.len);
        defer gpa.free(binding_flags);

        const sizes = try gpa.alloc(vk.DescriptorPoolSize, descriptors.len);
        errdefer gpa.free(sizes);

        for (bindings, binding_flags, sizes, descriptors, 0..) |*binding, *flags, *size, descriptor, i| {
            const t: vk.DescriptorType = switch (descriptor.t) {
                .uniform => .uniform_buffer,
                .image => .combined_image_sampler,
                .storage => .storage_buffer,
            };

            binding.* = .{
                .binding = @intCast(i),
                .descriptor_type = t,
                .descriptor_count = descriptor.count,
                .stage_flags = .{
                    .vertex_bit = descriptor.stages.vertex,
                    .fragment_bit = descriptor.stages.pixel,
                },
            };

            flags.* = .{
                .partially_bound_bit = descriptor.flags.partially_bound,
            };

            size.* = .{
                .type = t,
                .descriptor_count = descriptor.count,
            };
        }

        const flags_info: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
            .binding_count = @intCast(binding_flags.len),
            .p_binding_flags = @ptrCast(binding_flags.ptr),
        };

        const layout = device.vk.device.createDescriptorSetLayout(&.{
            .binding_count = @intCast(bindings.len),
            .p_bindings = @ptrCast(bindings.ptr),
            .p_next = @ptrCast(&flags_info),
        }, vk_alloc) catch |err| return switch (err) {
            error.OutOfHostMemory => error.OutOfMemory,
            error.OutOfDeviceMemory => error.OutOfDeviceMemory,
            error.Unknown => error.Unknown,
        };
        errdefer device.vk.device.destroyDescriptorSetLayout(layout, vk_alloc);

        return .{ .vk = .{
            .layout = layout,
            .sizes = sizes,
        } };
    }

    pub fn deinit(this: gpu.ResourceSet.Layout, device: gpu.Device) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroyDescriptorSetLayout(this.vk.layout, vk_alloc);
        device.vk.gpa.free(this.vk.sizes);
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
