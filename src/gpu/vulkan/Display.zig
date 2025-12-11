const std = @import("std");
const tracy = @import("tracy");
const platform = @import("../../platform.zig");
const vk = @import("vulkan");
const Instance = @import("Instance.zig");
const Device = @import("Device.zig");
const RenderPass = @import("RenderPass.zig");
const Semaphore = @import("wait_objects.zig").Semaphore;
const Fence = @import("wait_objects.zig").Fence;
const Image = @import("Image.zig");

image_size: @Vector(2, u32),
images: []Image,
image_views: []Image.View,
_swapchain: vk.SwapchainKHR,
_surface: vk.SurfaceKHR,
_surface_format: vk.SurfaceFormatKHR,
_instance: vk.InstanceProxy,
_device: *Device,

pub fn init(device: *Device, window: *platform.Window, alloc: std.mem.Allocator) !@This() {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const instance = device.instance;
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    // TODO: change createSurface function to accept ?*vk.AllocationCallbacks
    const surface = try platform.vulkan.createSurface(window, instance._instance);
    errdefer instance._instance.destroySurfaceKHR(surface, vk_alloc);

    const surface_format = try chooseSurfaceFormat(instance._instance.wrapper, device._phys, surface, alloc);
    var this: @This() = .{
        .image_size = undefined,
        .images = &.{},
        .image_views = &.{},
        ._swapchain = .null_handle,
        ._surface = surface,
        ._surface_format = surface_format,
        ._instance = instance._instance,
        ._device = device,
    };

    try this.initSwapchain(window.getFramebufferSize(), alloc);

    return this;
}

pub fn deinit(this: *@This(), alloc: std.mem.Allocator) void {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.deinitSwapchain(alloc);
    this._device._device.destroySwapchainKHR(this._swapchain, vk_alloc);
    this._instance.destroySurfaceKHR(this._surface, vk_alloc);
}

pub const initRenderPass = RenderPass.init;

pub const ImageIndex = u32;
const AcquireImageIndexResult = union(PresentResult) {
    success: ImageIndex,
    suboptimal: ImageIndex,
    out_of_date: void,
};

pub fn acquireImageIndex(this: *@This(), maybe_signal_semaphore: ?Semaphore, maybe_signal_fence: ?Fence, timeout_ns: u64) !AcquireImageIndexResult {
    const native_semaphore = if (maybe_signal_semaphore) |x| x._semaphore else .null_handle;
    const native_fence = if (maybe_signal_fence) |x| x._fence else .null_handle;

    const result = this._device._device.acquireNextImageKHR(this._swapchain, timeout_ns, native_semaphore, native_fence) catch |err| switch (err) {
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

pub fn releaseImageIndex(this: *@This(), index: u32) !void {
    try this._device._device.releaseSwapchainImagesEXT(&.{
        .image_index_count = 1,
        .p_image_indices = &index,
    });
}

const PresentResult = enum {
    success,
    suboptimal,
    out_of_date,
};

pub fn presentImage(this: *@This(), index: u32, wait_semaphores: []const Semaphore, maybe_signal_fence: ?Fence) !PresentResult {
    const maybe_fence_info: ?vk.SwapchainPresentFenceInfoEXT = if (maybe_signal_fence) |fence| .{
        .swapchain_count = 1,
        .p_fences = @ptrCast(&fence._fence),
    } else null;

    const result = this._device._device.queuePresentKHR(this._device._queue, &.{
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = Semaphore._nativesFromSlice(wait_semaphores),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&this._swapchain),
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

pub fn rebuild(this: *@This(), image_size: @Vector(2, u32), alloc: std.mem.Allocator) !void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain = this._swapchain;
    this.deinitSwapchain(alloc);
    try this.initSwapchain(image_size, alloc);
    this._device._device.destroySwapchainKHR(old_swapchain, vk_alloc);
}

fn initSwapchain(this: *@This(), image_size: @Vector(2, u32), alloc: std.mem.Allocator) !void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain: vk.SwapchainKHR = this._swapchain;
    this.image_size = image_size;

    const capabilities = try this._instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this._device._phys, this._surface);

    var min_image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0 and min_image_count > capabilities.max_image_count) {
        min_image_count = capabilities.max_image_count;
    }

    const extent = try this.chooseSwapExtent(image_size);
    this._swapchain = try this._device._device.createSwapchainKHR(&.{
        .surface = this._surface,
        .min_image_count = min_image_count,
        .image_format = this._surface_format.format,
        .image_color_space = this._surface_format.color_space,
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

    const images = try this._device._device.getSwapchainImagesAllocKHR(this._swapchain, alloc);
    errdefer alloc.free(images);
    this.images = @ptrCast(images);

    const image_views = try alloc.alloc(vk.ImageView, images.len);
    errdefer alloc.free(this.image_views);
    this.image_views = @ptrCast(image_views);
    for (images, image_views) |image, *image_view| {
        image_view.* = try this._device._device.createImageView(&.{
            .image = image,
            .view_type = .@"2d", // TODO: allow for different types
            .format = this._surface_format.format,
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

fn deinitSwapchain(this: *@This(), alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;

    for (this.image_views) |image_view| {
        this._device._device.destroyImageView(image_view._image_view, vk_alloc);
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

fn chooseSwapExtent(this: *const @This(), image_size: @Vector(2, u32)) !vk.Extent2D {
    const capabilities = try this._instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this._device._phys, this._surface);

    if (capabilities.current_extent.width != std.math.maxInt(u32))
        return capabilities.current_extent;

    return .{
        .width = std.math.clamp(image_size[0], capabilities.min_image_extent.width, capabilities.max_image_extent.width),
        .height = std.math.clamp(image_size[1], capabilities.min_image_extent.height, capabilities.max_image_extent.height),
    };
}
