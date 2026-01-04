const Image = @import("Image.zig");

color_image: Image,
color_image_view: Image.View,

pub const Desc = Descriptor;
pub const Descriptor = struct {
    color_format: Image.Format,
};
