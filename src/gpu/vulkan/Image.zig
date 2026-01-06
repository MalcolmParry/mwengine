const vk = @import("vulkan");
const Device = @import("Device.zig");

const Image = @This();

_image: vk.Image,

pub const View = struct {
    _image_view: vk.ImageView,
};

pub const Format = enum {
    bgra8_srgb,
    unknown,

    pub fn _toNative(format: Format) vk.Format {
        return switch (format) {
            .bgra8_srgb => .b8g8r8a8_srgb,
            .unknown => .undefined,
        };
    }

    pub fn _fromNative(format: vk.Format) Format {
        return switch (format) {
            .b8g8r8a8_srgb => .bgra8_srgb,
            else => .unknown,
        };
    }
};

pub const Layout = enum {
    undefined,
    color_attachment,
    present_src,

    pub fn _toNative(layout: Layout) vk.ImageLayout {
        return switch (layout) {
            .undefined => .undefined,
            .color_attachment => .color_attachment_optimal,
            .present_src => .present_src_khr,
        };
    }
};
