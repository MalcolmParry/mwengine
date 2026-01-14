const vk = @import("vulkan");
const gpu = @import("../../gpu.zig");

const Image = @This();
pub const Handle = Image;

image: vk.Image,

pub const View = struct {
    pub const Handle = View;

    image_view: vk.ImageView,
};

pub fn formatToNative(format: gpu.Image.Format) vk.Format {
    return switch (format) {
        .bgra8_srgb => .b8g8r8a8_srgb,
        .unknown => .undefined,
    };
}

pub fn formatFromNative(format: vk.Format) gpu.Image.Format {
    return switch (format) {
        .b8g8r8a8_srgb => .bgra8_srgb,
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
