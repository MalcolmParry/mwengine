const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const RenderPass = @import("RenderPass.zig");
const Image = @import("Image.zig");

_framebuffer: vk.Framebuffer,

pub fn init(device: *Device, render_pass_desc: RenderPass.Desc, image_size: @Vector(2, u32), image_views: []const Image.View) !@This() {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const framebuffer = try device._device.createFramebuffer(&.{
        .render_pass = render_pass_desc._render_pass,
        .attachment_count = @intCast(image_views.len),
        .p_attachments = @ptrCast(image_views.ptr),
        .width = image_size[0],
        .height = image_size[1],
        .layers = 1, // TODO: see what this is
    }, vk_alloc);

    return .{
        ._framebuffer = framebuffer,
    };
}

pub fn deinit(this: *@This(), device: *Device) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device._device.destroyFramebuffer(this._framebuffer, vk_alloc);
}
