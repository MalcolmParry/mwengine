const std = @import("std");
const gpu = @import("../gpu.zig");

pub const AnyObject = union(enum) {
    instance: gpu.Instance,
    device: gpu.Device,
    phys_device: gpu.Device.Physical,
    display: gpu.Display,
    shader: gpu.Shader,
    graphics_pipeline: gpu.GraphicsPipeline,
    semaphore: gpu.Semaphore,
    fence: gpu.Fence,
    resource_set: gpu.ResourceSet,
    resource_layout: gpu.ResourceSet.Layout,
    buffer: gpu.Buffer,
    image: gpu.Image,
    image_view: gpu.Image.View,
    cmd_encoder: gpu.CommandEncoder,

    pub fn deinit(this: AnyObject, device: gpu.Device, alloc: std.mem.Allocator) void {
        switch (this) {
            .instance => |_| @panic("invalid type"),
            .device => |_| @panic("invalid type"),
            .phys_device => |_| @panic("invalid type"),
            .display => |_| @panic("invalid type"),
            .shader => |x| x.deinit(device, alloc),
            .graphics_pipeline => |x| x.deinit(device, alloc),
            .semaphore => |x| x.deinit(device),
            .fence => |x| x.deinit(device),
            .resource_layout => |x| x.deinit(device, alloc),
            .resource_set => |x| x.deinit(device, alloc),
            .buffer => |x| x.deinit(device, alloc),
            .image => |x| x.deinit(device, alloc),
            .image_view => |x| x.deinit(device, alloc),
            .cmd_encoder => |x| x.deinit(device),
        }
    }

    pub fn deinitAll(these: []AnyObject, device: gpu.Device, alloc: std.mem.Allocator) void {
        for (these) |*this| {
            this.deinit(device, alloc);
        }
    }

    pub fn deinitAllReversed(these: []AnyObject, device: gpu.Device, alloc: std.mem.Allocator) void {
        for (0..these.len) |j| {
            const i = these.len - j - 1;
            const this = &these[i];
            this.deinit(device, alloc);
        }
    }
};
