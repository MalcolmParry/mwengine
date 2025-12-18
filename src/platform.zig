const builtin = @import("builtin");
const build_options = @import("build_options");

const impl = if (build_options.use_glfw) @import("platform/glfw.zig") else switch (builtin.os.tag) {
    // .linux => @import("platform/linux.zig"),
    else => @compileError("Platform not supported."),
};

pub const Window = impl.Window;
pub const vulkan = impl.vulkan;
