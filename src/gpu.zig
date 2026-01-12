const std = @import("std");
const platform = @import("platform.zig");
const vk = @import("gpu/vulkan.zig");

pub const CommandEncoder = vk.CommandEncoder;
pub const Semaphore = vk.Semaphore;
pub const Fence = vk.Fence;
pub const Buffer = vk.Buffer;
pub const ResourceSet = vk.ResourceSet;
pub const Image = vk.Image;

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

pub const Display = union(Api) {
    vk: vk.Display.Handle,

    pub fn init(device: Device, window: *platform.Window, alloc: std.mem.Allocator) anyerror!Display {
        return call(device, @src(), "Display", .{ device, window, alloc });
    }

    pub fn deinit(this: Display, alloc: std.mem.Allocator) void {
        return call(this, @src(), "Display", .{ this, alloc });
    }

    pub const ImageIndex = u32;
    pub const AcquireImageIndexResult = union(PresentResult) {
        success: ImageIndex,
        suboptimal: ImageIndex,
        out_of_date: void,
    };

    pub fn acquireImageIndex(this: Display, maybe_signal_semaphore: ?Semaphore, maybe_signal_fence: ?Fence, timeout_ns: u64) anyerror!AcquireImageIndexResult {
        return call(this, @src(), "Display", .{ this, maybe_signal_semaphore, maybe_signal_fence, timeout_ns });
    }

    pub const PresentResult = enum {
        success,
        suboptimal,
        out_of_date,
    };

    pub fn presentImage(this: Display, index: u32, wait_semaphores: []const Semaphore, maybe_signal_fence: ?Fence) anyerror!PresentResult {
        return call(this, @src(), "Display", .{ this, index, wait_semaphores, maybe_signal_fence });
    }

    pub fn rebuild(this: Display, image_size: @Vector(2, u32), alloc: std.mem.Allocator) anyerror!void {
        return call(this, @src(), "Display", .{ this, image_size, alloc });
    }

    pub fn imageFormat(this: Display) Image.Format {
        return call(this, @src(), "Display", .{this});
    }

    pub fn imageCount(this: Display) usize {
        return call(this, @src(), "Display", .{this});
    }

    pub fn imageSize(this: Display) @Vector(2, u32) {
        return call(this, @src(), "Display", .{this});
    }

    pub fn image(this: Display, index: Display.ImageIndex) Image {
        return call(this, @src(), "Display", .{ this, index });
    }

    pub fn imageView(this: Display, index: Display.ImageIndex) Image.View {
        return call(this, @src(), "Display", .{ this, index });
    }
};

pub const Shader = union {
    vk: vk.Shader.Handle,

    pub fn fromSpirv(device: Device, stage: Stage, spirvByteCode: []const u32, alloc: std.mem.Allocator) anyerror!Shader {
        return call(device, @src(), "Shader", .{ device, stage, spirvByteCode, alloc });
    }

    pub fn deinit(this: Shader, device: Device, alloc: std.mem.Allocator) void {
        return call(device, @src(), "Shader", .{ this, device, alloc });
    }

    pub const Stage = enum {
        vertex,
        pixel,
    };

    pub const StageFlags = packed struct {
        vertex: bool = false,
        pixel: bool = false,
    };

    pub const Set = union {
        vk: vk.Shader.Set.Handle,

        pub fn init(device: Device, vertex: Shader, pixel: Shader, per_vertex: []const DataType, alloc: std.mem.Allocator) anyerror!Set {
            return call(device, @src(), .{ "Shader", "Set" }, .{ device, vertex, pixel, per_vertex, alloc });
        }

        pub fn deinit(this: Set, device: Device, alloc: std.mem.Allocator) void {
            return call(device, @src(), .{ "Shader", "Set" }, .{ this, device, alloc });
        }
    };

    pub const DataType = enum {
        uint8,
        uint8x2,
        uint8x3,
        uint8x4,
        uint16,
        uint16x2,
        uint16x3,
        uint16x4,
        uint32,
        uint32x2,
        uint32x3,
        uint32x4,
        sint8,
        sint8x2,
        sint8x3,
        sint8x4,
        sint16,
        sint16x2,
        sint16x3,
        sint16x4,
        sint32,
        sint32x2,
        sint32x3,
        sint32x4,
        float16,
        float16x2,
        float16x3,
        float16x4,
        float32,
        float32x2,
        float32x3,
        float32x4,
        float32x4x4,

        pub fn size(this: @This()) usize {
            return switch (this) {
                .uint8 => 1,
                .uint8x2 => 2,
                .uint8x3 => 3,
                .uint8x4 => 4,
                .uint16 => 2,
                .uint16x2 => 4,
                .uint16x3 => 6,
                .uint16x4 => 8,
                .uint32 => 4,
                .uint32x2 => 8,
                .uint32x3 => 12,
                .uint32x4 => 16,
                .uint64 => 8,
                .uint64x2 => 16,
                .uint64x3 => 24,
                .uint64x4 => 32,
                .sint8 => 1,
                .sint8x2 => 2,
                .sint8x3 => 3,
                .sint8x4 => 4,
                .sint16 => 2,
                .sint16x2 => 4,
                .sint16x3 => 6,
                .sint16x4 => 8,
                .sint32 => 4,
                .sint32x2 => 8,
                .sint32x3 => 12,
                .sint32x4 => 16,
                .float32 => 4,
                .float32x2 => 8,
                .float32x3 => 12,
                .float32x4 => 16,
                .float32x4x4 => 64,
            };
        }
    };
};

pub const GraphicsPipeline = union {
    vk: vk.GraphicsPipeline.Handle,

    pub const CreateInfo = struct {
        alloc: std.mem.Allocator,
        render_target_desc: RenderTarget.Desc,
        shader_set: Shader.Set,
        resource_layouts: []const ResourceSet.Layout,
    };

    pub fn init(device: Device, info: CreateInfo) anyerror!GraphicsPipeline {
        return call(device, @src(), "GraphicsPipeline", .{ device, info });
    }

    pub fn deinit(this: GraphicsPipeline, device: Device, alloc: std.mem.Allocator) void {
        return call(device, @src(), "GraphicsPipeline", .{ this, device, alloc });
    }
};

pub const RenderTarget = struct {
    color_clear_value: @Vector(4, f32),
    color_image_view: Image.View,

    pub const Desc = Descriptor;
    pub const Descriptor = struct {
        color_format: Image.Format,
    };
};

fn call(api: Api, comptime src: std.builtin.SourceLocation, comptime type_name: anytype, args: anytype) CallRetType(src, type_name) {
    const fn_name = src.fn_name;

    switch (api) {
        .vk => {
            const T = GetTypeFromName(vk, type_name);

            const func = @field(T, fn_name);
            return @call(.auto, func, args);
        },
    }
}

fn CallRetType(comptime src: std.builtin.SourceLocation, comptime type_name: anytype) type {
    const fn_name = src.fn_name;
    const T = GetTypeFromName(@This(), type_name);
    const func = @field(T, fn_name);
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}

fn GetTypeFromName(Base: type, comptime type_name: anytype) type {
    return switch (@typeInfo(@TypeOf(type_name))) {
        .@"struct" => |x| blk: {
            var T = Base;
            for (x.fields) |field| {
                const name = @field(type_name, field.name);
                T = @field(T, name);
            }
            break :blk T;
        },
        else => @field(Base, type_name),
    };
}
