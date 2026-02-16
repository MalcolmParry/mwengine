const std = @import("std");
const vk = @import("vulkan");
const gpu = @import("../../gpu.zig");
const Device = @import("Device.zig");

const Image = @This();
pub const Handle = *Image;

memory_region: Device.MemoryRegion,
image: vk.Image,
format_: gpu.Image.Format,

pub fn init(device: gpu.Device, info: gpu.Image.InitInfo) !gpu.Image {
    const this = try info.alloc.create(Image);
    errdefer info.alloc.destroy(this);

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.image = try device.vk.device.createImage(&.{
        .image_type = .@"2d",
        .extent = .{
            .width = info.size[0],
            .height = info.size[1],
            .depth = 1,
        },
        .mip_levels = 1,
        .array_layers = 1,
        .format = formatToNative(info.format),
        .tiling = .optimal,
        .initial_layout = .undefined,
        .usage = .{
            .sampled_bit = info.usage.sampled,
            .transfer_dst_bit = info.usage.dst,
            .color_attachment_bit = info.usage.color_attachment,
            .depth_stencil_attachment_bit = info.usage.depth_stencil_attachment,
        },
        .samples = .{ .@"1_bit" = true },
        .sharing_mode = .exclusive,
    }, vk_alloc);
    errdefer device.vk.device.destroyImage(this.image, vk_alloc);

    const properties: vk.MemoryPropertyFlags = switch (info.loc) {
        .host => .{ .host_coherent_bit = true },
        .device => .{ .device_local_bit = true },
    };

    this.memory_region = try device.vk.allocateMemory(device.vk.device.getImageMemoryRequirements(this.image), properties);
    errdefer device.vk.freeMemory(this.memory_region);
    try device.vk.device.bindImageMemory(this.image, this.memory_region.memory, this.memory_region.offset);

    this.format_ = info.format;
    return .{ .vk = this };
}

pub fn deinit(this: gpu.Image, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyImage(this.vk.image, vk_alloc);
    device.vk.freeMemory(this.vk.memory_region);
    alloc.destroy(this.vk);
}

pub fn format(this: gpu.Image, device: gpu.Device) gpu.Image.Format {
    _ = device;
    return this.vk.format;
}

pub const View = struct {
    pub const Handle = View;

    image_view: vk.ImageView,

    pub fn init(device: gpu.Device, image: gpu.Image, aspect: gpu.Image.Aspect, alloc: std.mem.Allocator) !gpu.Image.View {
        var this: View = undefined;

        _ = alloc;
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        this.image_view = try device.vk.device.createImageView(&.{
            .image = image.vk.image,
            .view_type = .@"2d",
            .format = formatToNative(image.vk.format_),
            .components = .{
                .r = .identity,
                .b = .identity,
                .g = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = aspectToNative(aspect),
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, vk_alloc);

        return .{ .vk = this };
    }

    pub fn deinit(this: gpu.Image.View, device: gpu.Device, alloc: std.mem.Allocator) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        _ = alloc;
        device.vk.device.destroyImageView(this.vk.image_view, vk_alloc);
    }
};

pub fn formatToNative(format_: gpu.Image.Format) vk.Format {
    return switch (format_) {
        .rgba8_srgb => .r8g8b8a8_srgb,
        .bgra8_srgb => .b8g8r8a8_srgb,
        .d32_sfloat => .d32_sfloat,
        .unknown => .undefined,
    };
}

pub fn formatFromNative(format_: vk.Format) gpu.Image.Format {
    return switch (format_) {
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
