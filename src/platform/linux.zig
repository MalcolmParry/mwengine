const std = @import("std");
const window_impl = @import("x11.zig");

pub const Window = window_impl.Window;
pub const vulkan = struct {
    const vk = @import("vulkan");

    pub const createSurface = window_impl.vulkan.createSurface;
    pub const getRequiredInstanceExtensions = window_impl.vulkan.getRequiredInstanceExtensions;

    pub const Wrapper = struct {
        _lib_vulkan: std.DynLib,

        pub fn init() !@This() {
            var lib_vulkan = try std.DynLib.open("libvulkan.so.1");
            errdefer lib_vulkan.close();
            return .{
                ._lib_vulkan = lib_vulkan,
            };
        }

        pub fn deinit(this: *@This()) void {
            this._lib_vulkan.close();
        }

        pub fn getBaseWrapper(this: *@This()) !vk.BaseWrapper {
            const loader = this._lib_vulkan.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse return error.APIUnavailable;
            return vk.BaseWrapper.load(loader);
        }
    };
};
