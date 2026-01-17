const std = @import("std");
const gpu = @import("../../gpu.zig");
const Window = @import("../../Window.zig");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const Image = @import("Image.zig");

const Display = @This();
pub const Handle = *Display;

window: *Window,
swapchain: vk.SwapchainKHR,
surface: vk.SurfaceKHR,
surface_format: vk.SurfaceFormatKHR,
instance: vk.InstanceProxy,
device: gpu.Device,

image_size: @Vector(2, u32),
image_index: u32,
images: []gpu.Image,
image_views: []gpu.Image.View,

wait_obect_index: u32,
image_ready_semaphores: []gpu.Semaphore,
render_finished_semaphores: []gpu.Semaphore,
presented_fences: []gpu.Fence,

pub fn init(device: gpu.Device, window: *Window, alloc: std.mem.Allocator) !gpu.Display {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const this = try alloc.create(Display);
    errdefer alloc.destroy(this);

    this.window = window;
    this.instance = device.vk.instance.instance;
    this.device = device;
    this.swapchain = .null_handle;
    this.wait_obect_index = 0;
    this.surface = try Window.vulkan.createSurface(window, this.instance);
    errdefer this.instance.destroySurfaceKHR(this.surface, vk_alloc);

    this.surface_format = try chooseSurfaceFormat(this.instance.wrapper, device.vk.phys, this.surface, alloc);

    try this.initSwapchain(window.getFramebufferSize(), alloc);

    return .{ .vk = this };
}

pub fn deinit(this: gpu.Display, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    this.vk.deinitSwapchain(alloc);
    this.vk.device.vk.device.destroySwapchainKHR(this.vk.swapchain, vk_alloc);
    this.vk.instance.destroySurfaceKHR(this.vk.surface, vk_alloc);
    alloc.destroy(this.vk);
}

pub fn startFrame(this: gpu.Display, alloc: std.mem.Allocator) !void {
    try this.vk.presented_fences[this.vk.wait_obect_index].wait(this.vk.device, std.time.ns_per_s);

    const result = try this.vk.device.vk.device.acquireNextImageKHR(
        this.vk.swapchain,
        std.time.ns_per_ms * 100,
        this.vk.image_ready_semaphores[this.vk.wait_obect_index].vk.semaphore,
        .null_handle,
    );

    switch (result.result) {
        .success => {},
        .suboptimal_khr => try rebuild(this, alloc),
        .timeout => return error.Timeout,
        .not_ready => return error.NotReady,
        else => unreachable,
    }

    this.vk.image_index = result.image_index;
}

pub fn endFrame(this: gpu.Display, alloc: std.mem.Allocator) !void {
    const fence = this.vk.presented_fences[this.vk.wait_obect_index];
    const semaphore = this.vk.render_finished_semaphores[this.vk.wait_obect_index];
    try fence.reset(this.vk.device);

    const fence_info: vk.SwapchainPresentFenceInfoEXT = .{
        .swapchain_count = 1,
        .p_fences = @ptrCast(&fence.vk.fence),
    };

    const result = try this.vk.device.vk.device.queuePresentKHR(this.vk.device.vk.queue, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast(&semaphore.vk.semaphore),
        .swapchain_count = 1,
        .p_swapchains = @ptrCast(&this.vk.swapchain),
        .p_image_indices = @ptrCast(&this.vk.image_index),
        .p_results = null,
        .p_next = @ptrCast(&fence_info),
    });

    this.vk.wait_obect_index = (this.vk.wait_obect_index + 1) % @as(u32, @intCast(this.vk.images.len));
    return switch (result) {
        .success => {},
        .suboptimal_khr => rebuild(this, alloc),
        else => unreachable,
    };
}

pub fn rebuild(this: gpu.Display, alloc: std.mem.Allocator) !void {
    for (this.vk.presented_fences) |fence| {
        try fence.wait(this.vk.device, std.time.ms_per_s);
    }

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain = this.vk.swapchain;
    this.vk.deinitSwapchain(alloc);
    try this.vk.initSwapchain(this.vk.window.getFramebufferSize(), alloc);
    this.vk.device.vk.device.destroySwapchainKHR(old_swapchain, vk_alloc);
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

pub fn image(this: gpu.Display) gpu.Image {
    return this.vk.images[this.vk.image_index];
}

pub fn imageView(this: gpu.Display) gpu.Image.View {
    return this.vk.image_views[this.vk.image_index];
}

pub fn imageReadySemaphore(this: gpu.Display) gpu.Semaphore {
    return this.vk.image_ready_semaphores[this.vk.wait_obect_index];
}

pub fn renderFinishedSemaphore(this: gpu.Display) gpu.Semaphore {
    return this.vk.render_finished_semaphores[this.vk.wait_obect_index];
}

pub fn presentFinishedFence(this: gpu.Display) gpu.Fence {
    return this.vk.presented_fences[this.vk.wait_obect_index];
}

fn initSwapchain(this: *Display, image_size: @Vector(2, u32), alloc: std.mem.Allocator) !void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const old_swapchain: vk.SwapchainKHR = this.swapchain;
    this.image_size = image_size;

    const capabilities = try this.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this.device.vk.phys, this.surface);

    var min_image_count = capabilities.min_image_count + 1;
    if (capabilities.max_image_count > 0 and min_image_count > capabilities.max_image_count) {
        min_image_count = capabilities.max_image_count;
    }

    const extent = try this.chooseSwapExtent(image_size);
    this.swapchain = try this.device.vk.device.createSwapchainKHR(&.{
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

    const images = try this.device.vk.device.getSwapchainImagesAllocKHR(this.swapchain, alloc);
    errdefer alloc.free(images);
    this.images = @ptrCast(images);

    const image_views = try alloc.alloc(vk.ImageView, images.len);
    errdefer alloc.free(this.image_views);
    this.image_views = @ptrCast(image_views);
    for (images, image_views) |img, *img_view| {
        img_view.* = try this.device.vk.device.createImageView(&.{
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

    this.wait_obect_index = 0;
    this.image_ready_semaphores = try alloc.alloc(gpu.Semaphore, images.len);
    this.render_finished_semaphores = try alloc.alloc(gpu.Semaphore, images.len);
    this.presented_fences = try alloc.alloc(gpu.Fence, images.len);
    for (this.image_ready_semaphores, this.render_finished_semaphores, this.presented_fences) |*a, *b, *c| {
        a.* = try .init(this.device);
        b.* = try .init(this.device);
        c.* = try .init(this.device, true);
    }
}

fn deinitSwapchain(this: *Display, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;

    for (this.image_views, this.image_ready_semaphores, this.render_finished_semaphores, this.presented_fences) |image_view, a, b, c| {
        this.device.vk.device.destroyImageView(image_view.vk.image_view, vk_alloc);
        a.deinit(this.device);
        b.deinit(this.device);
        c.deinit(this.device);
    }

    alloc.free(this.image_views);
    alloc.free(this.images);
    alloc.free(this.image_ready_semaphores);
    alloc.free(this.render_finished_semaphores);
    alloc.free(this.presented_fences);
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
    const capabilities = try this.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(this.device.vk.phys, this.surface);

    if (capabilities.current_extent.width != std.math.maxInt(u32))
        return capabilities.current_extent;

    return .{
        .width = std.math.clamp(image_size[0], capabilities.min_image_extent.width, capabilities.max_image_extent.width),
        .height = std.math.clamp(image_size[1], capabilities.min_image_extent.height, capabilities.max_image_extent.height),
    };
}
