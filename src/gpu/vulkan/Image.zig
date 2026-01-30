const std = @import("std");
const vk = @import("vulkan");
const gpu = @import("../../gpu.zig");
const Device = @import("Device.zig");

const Image = @This();
pub const Handle = *Image;

memory_region: Device.MemoryRegion,
image: vk.Image,

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

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Image, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyImage(this.vk.image, vk_alloc);
    device.vk.freeMemory(this.vk.memory_region);
    alloc.destroy(this.vk);
}

pub const View = struct {
    pub const Handle = View;

    image_view: vk.ImageView,
};

pub fn formatToNative(format: gpu.Image.Format) vk.Format {
    return switch (format) {
        .bgra8_srgb => .b8g8r8a8_srgb,
        .d32_sfloat => .d32_sfloat,
        .unknown => .undefined,
    };
}

pub fn formatFromNative(format: vk.Format) gpu.Image.Format {
    return switch (format) {
        .b8g8r8a8_srgb => .bgra8_srgb,
        .d32_sfloat => .d32_sfloat,
        else => .unknown,
    };
}

pub fn layoutToNative(layout: gpu.Image.Layout) vk.ImageLayout {
    return switch (layout) {
        .undefined => .undefined,
        .color_attachment => .color_attachment_optimal,
        .present_src => .present_src_khr,
    };
}
