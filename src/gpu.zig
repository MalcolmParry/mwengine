const std = @import("std");
const vk = @import("gpu/vulkan.zig");

pub const Device = vk.Device;
pub const Display = vk.Display;
pub const Shader = vk.Shader;
pub const GraphicsPipeline = vk.GraphicsPipeline;
pub const CommandEncoder = vk.CommandEncoder;
pub const Semaphore = vk.Semaphore;
pub const Fence = vk.Fence;
pub const Buffer = vk.Buffer;
pub const ResourceSet = vk.ResourceSet;

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
