const std = @import("std");
const vk = @import("gpu/vulkan.zig");

pub const Display = vk.Display;
pub const Shader = vk.Shader;
pub const GraphicsPipeline = vk.GraphicsPipeline;
pub const CommandEncoder = vk.CommandEncoder;
pub const Semaphore = vk.Semaphore;
pub const Fence = vk.Fence;
pub const Buffer = vk.Buffer;
pub const ResourceSet = vk.ResourceSet;

pub const Size = u64;
pub const Api = enum {
    vk,
};

pub const Instance = union(Api) {
    vk: vk.Instance.Handle,

    pub fn api(this: Instance) Api {
        return @as(Api, this);
    }

    pub fn init(debug_logging: bool, alloc: std.mem.Allocator) anyerror!Instance {
        return call(.vk, @src(), "Instance", .{ debug_logging, alloc });
    }

    pub fn deinit(this: Instance, alloc: std.mem.Allocator) void {
        return call(this.api(), @src(), "Instance", .{ this, alloc });
    }

    pub fn bestPhysicalDevice(this: Instance) anyerror!Device.Physical {
        return call(this.api(), @src(), "Instance", .{this});
    }

    pub const initDevice = Device.init;
};

pub const Device = union(Api) {
    vk: vk.Device.Handle,

    pub const Physical = union {
        vk: vk.Device.Physical,
    };

    pub fn init(instance: Instance, physical_device: Physical, alloc: std.mem.Allocator) anyerror!Device {
        return call(instance, @src(), "Device", .{ instance, physical_device, alloc });
    }

    pub fn deinit(this: Device, alloc: std.mem.Allocator) void {
        return call(this, @src(), "Device", .{ this, alloc });
    }

    pub fn waitUntilIdle(this: Device) void {
        return call(this, @src(), "Device", .{this});
    }

    pub fn setBufferRegions(device: Device, regions: []const Buffer.Region, data: []const []const u8) !void {
        var offset: usize = 0;
        for (data, regions) |x, r| {
            std.debug.assert(x.len == r.size);
            offset += x.len;
        }

        var staging = try device.initBuffer(.{
            .loc = .host,
            .usage = .{ .src = true },
            .size = offset,
        });
        defer staging.deinit(device);
        const mapping = try staging.map(device);
        defer staging.unmap(device);

        offset = 0;
        for (data) |x| {
            @memcpy(mapping[offset .. offset + x.len], x);
            offset += x.len;
        }

        var fence = try device.initFence(false);
        defer fence.deinit(device);
        var command_encoder = try device.initCommandEncoder();
        defer command_encoder.deinit(device);

        try command_encoder.begin(device);
        offset = 0;
        for (regions) |r| {
            command_encoder.cmdCopyBuffer(device, .{
                .buffer = &staging,
                .size = r.size,
                .offset = offset,
            }, .{
                .buffer = r.buffer,
                .size = r.size,
                .offset = r.offset,
            });
            offset += r.size;
        }
        try command_encoder.end(device);
        try command_encoder.submit(device, &.{}, &.{}, fence);
        try fence.wait(device, std.time.ns_per_s);
    }

    pub const initDisplay = Display.init;
    pub const initBuffer = Buffer.init;
    pub const initResouceLayout = ResourceSet.Layout.init;
    pub const initResouceSet = ResourceSet.init;
    pub const initCommandEncoder = CommandEncoder.init;
    pub const initSemaphore = Semaphore.init;
    pub const initFence = Fence.init;
    pub const initGraphicsPipeline = GraphicsPipeline.init;
};

fn call(api: Api, comptime src: std.builtin.SourceLocation, comptime type_name: []const u8, args: anytype) CallRetType(src, type_name) {
    const fn_name = src.fn_name;

    switch (api) {
        .vk => {
            const func = @field(@field(vk, type_name), fn_name);
            return @call(.auto, func, args);
        },
    }
}

fn CallRetType(comptime src: std.builtin.SourceLocation, comptime type_name: []const u8) type {
    const fn_name = src.fn_name;
    const T = @field(@This(), type_name);
    const func = @field(T, fn_name);
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}
