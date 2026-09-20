const std = @import("std");
const vk = @import("vulkan");
const gpu = @import("../gpu.zig");
const Device = @import("Device.zig");

const Image = @This();
pub const Handle = Image;

image: vk.Image,
memory_region: Device.MemoryRegion,

pub fn init(device: gpu.Device, info: gpu.Image.InitInfo) gpu.Image.InitError!gpu.Image {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const image = device.vk.device.createImage(&.{
        .image_type = .@"2d",
        .extent = .{
            .width = info.size[0],
            .height = info.size[1],
            .depth = 1,
        },
        .mip_levels = info.mip_count,
        .array_layers = info.layer_count,
        .format = formatToNative(info.format),
        .tiling = .optimal,
        .initial_layout = .undefined,
        .usage = .{
            .sampled_bit = info.usage.sampled,
            .transfer_src_bit = info.usage.src,
            .transfer_dst_bit = info.usage.dst,
            .color_attachment_bit = info.usage.color_attachment,
            .depth_stencil_attachment_bit = info.usage.depth_stencil_attachment,
        },
        .samples = .{ .@"1_bit" = true },
        .sharing_mode = .exclusive,
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        // only happens with buffer device address
        error.InvalidOpaqueCaptureAddressKHR => unreachable,
        error.CompressionExhaustedEXT => error.CompressionExhaused,
        error.Unknown => error.Unknown,
    };
    errdefer device.vk.device.destroyImage(image, vk_alloc);

    const properties: vk.MemoryPropertyFlags = switch (info.loc) {
        .host => .{ .host_coherent_bit = true },
        .device => .{ .device_local_bit = true },
    };

    const memory_region = device.vk.allocateMemory(device.vk.device.getImageMemoryRequirements(image), properties, false) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.MemoryMapFailed => unreachable,
        error.NoSuitableMemoryType => error.NoSuitableMemoryType,
        error.Unknown => error.Unknown,
    };
    errdefer device.vk.freeMemory(memory_region);

    device.vk.device.bindImageMemory(image, memory_region.memory, memory_region.offset) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };

    return .{
        .format = info.format,
        .size = info.size,
        .impl = .{ .vk = .{
            .image = image,
            .memory_region = memory_region,
        } },
    };
}

pub fn deinit(image: gpu.Image, device: gpu.Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyImage(image.impl.vk.image, vk_alloc);
    device.vk.freeMemory(image.impl.vk.memory_region);
}

pub fn debugLabel(image: gpu.Image, device: gpu.Device, name: [:0]const u8) void {
    if (device.vk.instance.maybe_debug_messenger == null) return;
    device.vk.device.setDebugUtilsObjectNameEXT(&.{
        .object_type = .image,
        .object_handle = @intFromEnum(image.impl.vk.image),
        .p_object_name = name,
    }) catch {};
}

pub const View = struct {
    pub const Handle = View;

    image_view: vk.ImageView,

    pub fn init(device: gpu.Device, info: gpu.Image.View.InitInfo) gpu.Image.View.InitError!gpu.Image.View {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const image_view = device.vk.device.createImageView(&.{
            .image = info.image.impl.vk.image,
            .view_type = switch (info.kind) {
                .@"2d" => .@"2d",
                .array_2d => .@"2d_array",
            },
            .format = formatToNative(info.image.format),
            .components = .{
                .r = componentSwizzleToNative(info.component_mapping.r),
                .g = componentSwizzleToNative(info.component_mapping.g),
                .b = componentSwizzleToNative(info.component_mapping.b),
                .a = componentSwizzleToNative(info.component_mapping.a),
            },
            .subresource_range = .{
                .aspect_mask = aspectToNative(info.subresource_range.aspect),
                .base_mip_level = info.subresource_range.mip_offset,
                .level_count = switch (info.subresource_range.mip_count) {
                    .count => |x| x,
                    .all => vk.REMAINING_MIP_LEVELS,
                },
                .base_array_layer = info.subresource_range.layer_offset,
                .layer_count = switch (info.subresource_range.layer_count) {
                    .count => |x| x,
                    .all => vk.REMAINING_ARRAY_LAYERS,
                },
            },
        }, vk_alloc) catch |err| return switch (err) {
            error.OutOfHostMemory => error.OutOfMemory,
            error.OutOfDeviceMemory => error.OutOfDeviceMemory,
            // only happens with buffer device address
            error.InvalidOpaqueCaptureAddressKHR => unreachable,
            error.Unknown => error.Unknown,
        };

        return .{ .vk = .{ .image_view = image_view } };
    }

    pub fn deinit(this: gpu.Image.View, device: gpu.Device) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device.vk.device.destroyImageView(this.vk.image_view, vk_alloc);
    }

    pub fn debugLabel(view: gpu.Image.View, device: gpu.Device, name: [:0]const u8) void {
        if (device.vk.instance.maybe_debug_messenger == null) return;
        device.vk.device.setDebugUtilsObjectNameEXT(&.{
            .object_type = .image_view,
            .object_handle = @intFromEnum(view.vk.image_view),
            .p_object_name = name,
        }) catch {};
    }

    fn componentSwizzleToNative(x: gpu.Image.ComponentMapping.Swizzle) vk.ComponentSwizzle {
        return switch (x) {
            .identity => .identity,
            .zero => .zero,
            .one => .one,
            .r => .r,
            .g => .g,
            .b => .b,
            .a => .a,
        };
    }
};

pub fn formatToNative(format_: gpu.Image.Format) vk.Format {
    return switch (format_) {
        .r8_unorm => .r8_unorm,
        .r8_srgb => .r8_srgb,
        .rgba8_srgb => .r8g8b8a8_srgb,
        .bgra8_srgb => .b8g8r8a8_srgb,
        .d32_sfloat => .d32_sfloat,
        .unknown => .undefined,
    };
}

pub fn formatFromNative(format_: vk.Format) gpu.Image.Format {
    return switch (format_) {
        .r8_unorm => .r8_unorm,
        .r8_srgb => .r8_srgb,
        .r8g8b8a8_srgb => .rgba8_srgb,
        .b8g8r8a8_srgb => .bgra8_srgb,
        .d32_sfloat => .d32_sfloat,
        else => .unknown,
    };
}

pub fn layoutToNative(layout: gpu.Image.Layout) vk.ImageLayout {
    return switch (layout) {
        .undefined => .undefined,
        .color_attachment => .color_attachment_optimal,
        .depth_stencil => .depth_stencil_attachment_optimal,
        .present_src => .present_src_khr,
        .transfer_src => .transfer_src_optimal,
        .transfer_dst => .transfer_dst_optimal,
        .shader_read_only => .shader_read_only_optimal,
    };
}

pub fn aspectToNative(aspect: gpu.Image.Aspect) vk.ImageAspectFlags {
    return .{
        .color_bit = aspect.color,
        .depth_bit = aspect.depth,
    };
}

pub fn subresourceLayersToNative(subresource: gpu.Image.Subresource.Layers) vk.ImageSubresourceLayers {
    return .{
        .aspect_mask = aspectToNative(subresource.aspect),
        .base_array_layer = subresource.layer_offset,
        .layer_count = subresource.layer_count,
        .mip_level = subresource.mip_level,
    };
}
