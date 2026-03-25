const std = @import("std");
const gpu = @import("../../gpu.zig");
const Window = @import("../../Window.zig");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const Image = @import("Image.zig");

const Display = @This();
pub const Handle = *Display;

image_size: @Vector(2, u32),
images: []gpu.Image,
image_views: []gpu.Image.View,
swapchain: vk.SwapchainKHR,
surface: vk.SurfaceKHR,
surface_format: vk.SurfaceFormatKHR,
instance: vk.InstanceProxy,
device: *Device,

image_available_semaphores: []vk.Semaphore,
image_presentable_semaphores: []vk.Semaphore,

pool_index: usize,
image_available_semaphores_pool: []vk.Semaphore,

pub fn init(device: gpu.Device, window: *Window, alloc: std.mem.Allocator) gpu.Display.InitError!gpu.Display {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const this = try alloc.create(Display);
    errdefer alloc.destroy(this);

    this.instance = device.vk.instance.instance;
    this.device = device.vk;
    this.surface = try Window.vulkan.createSurface(window, this.instance);
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

pub fn acquireImageIndex(this: gpu.Display, timeout_ns: u64) gpu.Display.AcquireImageIndexError!gpu.Display.AcquireImageIndexResult {
    const native_semaphore = this.vk.image_available_semaphores_pool[this.vk.pool_index];
    this.vk.pool_index = (this.vk.pool_index + 1) % this.vk.images.len;

    const result = this.vk.device.device.acquireNextImageKHR(this.vk.swapchain, timeout_ns, native_semaphore, .null_handle) catch |err| return switch (err) {
        error.OutOfDateKHR => error.OutOfDate,
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.DeviceLost => error.DeviceLost,
        error.SurfaceLostKHR => error.SurfaceLost,
        // full screen not supported yet
        error.FullScreenExclusiveModeLostEXT,
        error.Unknown,
        => error.Unknown,
    };

    const optimal = switch (result.result) {
        .success => true,
        .suboptimal_khr => false,
        .timeout => return error.Timeout,
        // only happens when timeout is 0
        .not_ready => unreachable,
        else => unreachable,
    };

    this.vk.image_available_semaphores[result.image_index] = native_semaphore;
    return .{
        .image_index = result.image_index,
        .optimal = optimal,
    };
}

pub fn presentImage(this: gpu.Display, index: u32) gpu.Display.PresentImageError!void {
    const maybe_fence_info: ?vk.SwapchainPresentFenceInfoEXT = null;

    const result = this.vk.device.device.queuePresentKHR(this.vk.device.queue, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&this.vk.image_presentable_semaphores[index]),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&this.vk.swapchain),
        .p_image_indices = @ptrCast(&index),
        .p_results = null,
        .p_next = if (maybe_fence_info) |x| @ptrCast(&x) else null,
    }) catch |err| return switch (err) {
        error.OutOfDateKHR => error.OutOfDate,
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.DeviceLost => error.DeviceLost,
        error.SurfaceLostKHR => error.SurfaceLost,
        // full screen not supported yet
        error.FullScreenExclusiveModeLostEXT,
        error.Unknown,
        => error.Unknown,
    };

    return switch (result) {
        .success => {},
        .suboptimal_khr => error.Suboptimal,
        else => unreachable,
    };
}

pub fn rebuild(this: gpu.Display, image_size: @Vector(2, u32), alloc: std.mem.Allocator) gpu.Display.RebuildError!void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain = this.vk.swapchain;
    this.vk.deinitSwapchain(alloc);
    try this.vk.initSwapchain(image_size, alloc);
    this.vk.device.device.destroySwapchainKHR(old_swapchain, vk_alloc);
}

pub fn imageFormat(this: gpu.Display) gpu.Image.Format {
    return Image.formatFromNative(this.vk.surface_format.format);
}

pub fn imageCount(this: gpu.Display) usize {
    return this.vk.images.len;
}

pub fn imageSize(this: gpu.Display) @Vector(2, u32) {
    return this.vk.image_size;
}

pub fn image(this: gpu.Display, index: gpu.Display.ImageIndex) gpu.Image {
    return this.vk.images[index];
}

pub fn imageView(this: gpu.Display, index: gpu.Display.ImageIndex) gpu.Image.View {
    return this.vk.image_views[index];
}

fn initSwapchain(this: *Display, image_size: @Vector(2, u32), alloc: std.mem.Allocator) !void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain: vk.SwapchainKHR = this.swapchain;
    this.image_size = image_size;

    const capabilities = this.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this.device.phys, this.surface) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.SurfaceLostKHR => error.SurfaceLost,
        error.Unknown => error.Unknown,
    };

    var min_image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0 and min_image_count > capabilities.max_image_count) {
        min_image_count = capabilities.max_image_count;
    }

    const extent = try this.chooseSwapExtent(image_size);
    this.swapchain = this.device.device.createSwapchainKHR(&.{
        .surface = this.surface,
        .min_image_count = min_image_count,
        .image_format = this.surface_format.format,
        .image_color_space = this.surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{
            // TODO: allow user to specify
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
    }, vk_alloc) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.SurfaceLostKHR => error.SurfaceLost,
        error.DeviceLost => error.DeviceLost,
        error.InitializationFailed => error.InitFailed,
        error.NativeWindowInUseKHR => error.SurfaceInUse,
        error.CompressionExhaustedEXT,
        error.Unknown,
        => error.Unknown,
    };

    const images = this.device.device.getSwapchainImagesAllocKHR(this.swapchain, alloc) catch |err| return switch (err) {
        error.OutOfHostMemory, error.OutOfMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };
    defer alloc.free(images);

    this.images = try alloc.alloc(gpu.Image, images.len);
    errdefer alloc.free(this.images);
    const format = Image.formatFromNative(this.surface_format.format);
    for (this.images, images) |*x, native| {
        x.vk = try alloc.create(Image);
        x.vk.* = .{
            .image = native,
            .memory_region = undefined,
            .format_ = format,
        };
    }

    const image_views = try alloc.alloc(vk.ImageView, images.len);
    errdefer alloc.free(this.image_views);
    this.image_views = @ptrCast(image_views);
    for (images, image_views) |img, *img_view| {
        img_view.* = this.device.device.createImageView(&.{
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
        }, vk_alloc) catch |err| return switch (err) {
            error.OutOfHostMemory => error.OutOfMemory,
            error.OutOfDeviceMemory => error.OutOfDeviceMemory,
            error.InvalidOpaqueCaptureAddressKHR,
            error.Unknown,
            => error.Unknown,
        };
    }

    this.image_available_semaphores = try alloc.alloc(vk.Semaphore, images.len);
    errdefer alloc.free(this.image_available_semaphores);

    this.pool_index = 0;
    this.image_available_semaphores_pool = try alloc.alloc(vk.Semaphore, images.len);
    errdefer alloc.free(this.image_available_semaphores_pool);
    for (this.image_available_semaphores_pool) |*x| {
        x.* = this.device.device.createSemaphore(&.{}, vk_alloc) catch |err| return switch (err) {
            error.OutOfHostMemory => error.OutOfMemory,
            error.OutOfDeviceMemory => error.OutOfDeviceMemory,
            error.Unknown => error.Unknown,
        };
    }

    this.image_presentable_semaphores = try alloc.alloc(vk.Semaphore, images.len);
    errdefer alloc.free(this.image_presentable_semaphores);
    for (this.image_presentable_semaphores) |*x| {
        x.* = this.device.device.createSemaphore(&.{}, vk_alloc) catch |err| return switch (err) {
            error.OutOfHostMemory => error.OutOfMemory,
            error.OutOfDeviceMemory => error.OutOfDeviceMemory,
            error.Unknown => error.Unknown,
        };
    }
}

fn deinitSwapchain(this: *Display, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;

    for (this.images, this.image_views, this.image_available_semaphores_pool, this.image_presentable_semaphores) |img, view, available_semaphore, presentable_semaphore| {
        this.device.device.destroySemaphore(presentable_semaphore, vk_alloc);
        this.device.device.destroySemaphore(available_semaphore, vk_alloc);
        this.device.device.destroyImageView(view.vk.image_view, vk_alloc);
        alloc.destroy(img.vk);
    }

    alloc.free(this.images);
    alloc.free(this.image_views);
    alloc.free(this.image_available_semaphores);
    alloc.free(this.image_presentable_semaphores);
    alloc.free(this.image_available_semaphores_pool);
}

fn chooseSurfaceFormat(dispatch: *const vk.InstanceWrapper, phys: vk.PhysicalDevice, surface: vk.SurfaceKHR, alloc: std.mem.Allocator) !vk.SurfaceFormatKHR {
    const formats = dispatch.getPhysicalDeviceSurfaceFormatsAllocKHR(phys, surface, alloc) catch |err| return switch (err) {
        error.OutOfMemory, error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.SurfaceLostKHR => error.SurfaceLost,
        error.Unknown => error.Unknown,
    };
    defer alloc.free(formats);

    for (formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            return format;
        }
    }

    return formats[0];
}

fn chooseSwapExtent(this: *Display, image_size: @Vector(2, u32)) !vk.Extent2D {
    const capabilities = this.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this.device.phys, this.surface) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.SurfaceLostKHR => error.SurfaceLost,
        error.Unknown => error.Unknown,
    };

    if (capabilities.current_extent.width != std.math.maxInt(u32))
        return capabilities.current_extent;

    return .{
        .width = std.math.clamp(image_size[0], capabilities.min_image_extent.width, capabilities.max_image_extent.width),
        .height = std.math.clamp(image_size[1], capabilities.min_image_extent.height, capabilities.max_image_extent.height),
    };
}
