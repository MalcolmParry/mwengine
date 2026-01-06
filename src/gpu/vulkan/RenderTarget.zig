const Image = @import("Image.zig");

color_clear_value: @Vector(4, f32),
color_image_view: Image.View,

pub const Desc = Descriptor;
pub const Descriptor = struct {
    color_format: Image.Format,
};
