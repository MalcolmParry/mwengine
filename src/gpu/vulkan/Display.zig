const std = @import("std");
const gpu = @import("../../gpu.zig");
const platform = @import("../../platform.zig");
const vk = @import("vulkan");
const Instance = @import("Instance.zig");
const Device = @import("Device.zig");
const Semaphore = @import("wait_objects.zig").Semaphore;
const Image = @import("Image.zig");

const Display = @This();
pub const Handle = *Display;

image_size: @Vector(2, u32),
images: []Image,
image_views: []Image.View,
swapchain: vk.SwapchainKHR,
surface: vk.SurfaceKHR,
surface_format: vk.SurfaceFormatKHR,
instance: vk.InstanceProxy,
device: *Device,

pub fn init(device: gpu.Device, window: *platform.Window, alloc: std.mem.Allocator) !gpu.Display {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const this = try alloc.create(Display);
    errdefer alloc.destroy(this);

    this.instance = device.vk.instance.instance;
    this.device = device.vk;
    this.surface = try platform.vulkan.createSurface(window, this.instance);
    this.swapchain = .null_handle;
    errdefer this.instance.destroySurfaceKHR(this.surface, vk_alloc);

    this.surface_format = try chooseSurfaceFormat(this.instance.wrapper, device.vk.phys, this.surface, alloc);

    try this.initSwapchain(window.getFramebufferSize(), alloc);

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Display, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.vk.deinitSwapchain(alloc);
    this.vk.device.device.destroySwapchainKHR(this.vk.swapchain, vk_alloc);
    this.vk.instance.destroySurfaceKHR(this.vk.surface, vk_alloc);
    alloc.destroy(this.vk);
}

pub fn acquireImageIndex(this: gpu.Display, maybe_signal_semaphore: ?gpu.Semaphore, maybe_signal_fence: ?gpu.Fence, timeout_ns: u64) !gpu.Display.AcquireImageIndexResult {
    const native_semaphore = if (maybe_signal_semaphore) |x| x.vk.semaphore else .null_handle;
    const native_fence = if (maybe_signal_fence) |x| x.vk.fence else .null_handle;

    const result = this.vk.device.device.acquireNextImageKHR(this.vk.swapchain, timeout_ns, native_semaphore, native_fence) catch |err| switch (err) {
        error.OutOfDateKHR => return .out_of_date,
        else => return err,
    };

    return switch (result.result) {
        .success => .{ .success = result.image_index },
        .timeout => error.Timeout,
        .not_ready => error.NotReady,
        .suboptimal_khr => .{ .suboptimal = result.image_index },
        else => unreachable,
    };
}

pub fn presentImage(this: gpu.Display, index: u32, wait_semaphores: []const gpu.Semaphore, maybe_signal_fence: ?gpu.Fence) !gpu.Display.PresentResult {
    const maybe_fence_info: ?vk.SwapchainPresentFenceInfoEXT = if (maybe_signal_fence) |fence| .{
        .swapchain_count = 1,
        .p_fences = @ptrCast(&fence.vk.fence),
    } else null;

    const result = this.vk.device.device.queuePresentKHR(this.vk.device.queue, &.{
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = Semaphore.nativesFromSlice(wait_semaphores),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&this.vk.swapchain),
        .p_image_indices = @ptrCast(&index),
        .p_results = null,
        .p_next = if (maybe_fence_info) |x| @ptrCast(&x) else null,
    }) catch |err| return switch (err) {
        error.OutOfDateKHR => .out_of_date,
        else => err,
    };

    return switch (result) {
        .success => .success,
        .suboptimal_khr => .suboptimal,
        else => unreachable,
    };
}

pub fn rebuild(this: gpu.Display, image_size: @Vector(2, u32), alloc: std.mem.Allocator) !void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain = this.vk.swapchain;
    this.vk.deinitSwapchain(alloc);
    try this.vk.initSwapchain(image_size, alloc);
    this.vk.device.device.destroySwapchainKHR(old_swapchain, vk_alloc);
}

pub fn imageFormat(this: gpu.Display) Image.Format {
    return Image.Format._fromNative(this.vk.surface_format.format);
}

pub fn imageCount(this: gpu.Display) usize {
    return this.vk.images.len;
}

pub fn imageSize(this: gpu.Display) @Vector(2, u32) {
    return this.vk.image_size;
}

pub fn image(this: gpu.Display, index: gpu.Display.ImageIndex) Image {
    return this.vk.images[index];
}

pub fn imageView(this: gpu.Display, index: gpu.Display.ImageIndex) Image.View {
    return this.vk.image_views[index];
}

fn initSwapchain(this: *Display, image_size: @Vector(2, u32), alloc: std.mem.Allocator) !void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain: vk.SwapchainKHR = this.swapchain;
    this.image_size = image_size;

    const capabilities = try this.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this.device.phys, this.surface);

    var min_image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0 and min_image_count > capabilities.max_image_count) {
        min_image_count = capabilities.max_image_count;
    }

    const extent = try this.chooseSwapExtent(image_size);
    this.swapchain = try this.device.device.createSwapchainKHR(&.{
        .surface = this.surface,
        .min_image_count = min_image_count,
        .image_format = this.surface_format.format,
        .image_color_space = this.surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{
            .color_attachment_bit = true,
        },
        .image_sharing_mode = .exclusive,
        // these don't need to be specified unless sharing mode is .concurrent
        .queue_family_index_count = 0,
        .p_queue_family_indices = null,
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{
            .opaque_bit_khr = true,
        },
        .present_mode = .immediate_khr,
        .clipped = .true,
        .old_swapchain = old_swapchain,
    }, vk_alloc);

    const images = try this.device.device.getSwapchainImagesAllocKHR(this.swapchain, alloc);
    errdefer alloc.free(images);
    this.images = @ptrCast(images);

    const image_views = try alloc.alloc(vk.ImageView, images.len);
    errdefer alloc.free(this.image_views);
    this.image_views = @ptrCast(image_views);
    for (images, image_views) |img, *img_view| {
        img_view.* = try this.device.device.createImageView(&.{
            .image = img,
            .view_type = .@"2d", // TODO: allow for different types
            .format = this.surface_format.format,
            .components = .{
                .r = .identity,
                .b = .identity,
                .g = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{
                    .color_bit = true,
                },
                .base_mip_level = 0, // TODO: allow for mip mapping
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, vk_alloc);
    }
}

fn deinitSwapchain(this: *Display, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;

    for (this.image_views) |image_view| {
        this.device.device.destroyImageView(image_view._image_view, vk_alloc);
    }

    alloc.free(this.image_views);
    alloc.free(this.images);
}

fn chooseSurfaceFormat(dispatch: *const vk.InstanceWrapper, phys: vk.PhysicalDevice, surface: vk.SurfaceKHR, alloc: std.mem.Allocator) !vk.SurfaceFormatKHR {
    const formats = try dispatch.getPhysicalDeviceSurfaceFormatsAllocKHR(phys, surface, alloc);
    defer alloc.free(formats);

    for (formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            return format;
        }
    }

    return formats[0];
}

fn chooseSwapExtent(this: *Display, image_size: @Vector(2, u32)) !vk.Extent2D {
    const capabilities = try this.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this.device.phys, this.surface);

    if (capabilities.current_extent.width != std.math.maxInt(u32))
        return capabilities.current_extent;

    return .{
        .width = std.math.clamp(image_size[0], capabilities.min_image_extent.width, capabilities.max_image_extent.width),
        .height = std.math.clamp(image_size[1], capabilities.min_image_extent.height, capabilities.max_image_extent.height),
    };
}
