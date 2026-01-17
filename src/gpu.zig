const std = @import("std");
const Window = @import("Window.zig");
const vk = @import("gpu/vulkan.zig");

pub const Size = u64;
pub const SizeOrWhole = union(enum) {
    size: Size,
    whole,
};

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
        var alloc_buffer: [64]u8 = undefined;
        var alloc_obj = std.heap.FixedBufferAllocator.init(&alloc_buffer);
        const alloc = alloc_obj.allocator();
        std.debug.assert(regions.len == data.len);

        var offset: usize = 0;
        for (data, regions) |x, r| {
            std.debug.assert(x.len == r.size(device));
            offset += x.len;
        }

        var staging = try device.initBuffer(.{
            .alloc = alloc,
            .loc = .host,
            .usage = .{ .src = true },
            .size = offset,
        });
        defer staging.deinit(device, alloc);
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
            const size = r.size(device);
            command_encoder.cmdCopyBuffer(device, .{
                .buffer = staging,
                .size_or_whole = .{ .size = size },
                .offset = offset,
            }, r);
            offset += size;
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

    pub fn init(device: Device, window: *Window, alloc: std.mem.Allocator) anyerror!Display {
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

pub const Semaphore = union {
    vk: vk.Semaphore.Handle,

    pub fn init(device: Device) anyerror!Semaphore {
        return call(device, @src(), "Semaphore", .{device});
    }

    pub fn deinit(this: Semaphore, device: Device) void {
        return call(device, @src(), "Semaphore", .{ this, device });
    }
};

pub const Fence = union {
    vk: vk.Fence.Handle,

    pub fn init(device: Device, signaled: bool) anyerror!Fence {
        return call(device, @src(), "Fence", .{ device, signaled });
    }

    pub fn deinit(this: Fence, device: Device) void {
        return call(device, @src(), "Fence", .{ this, device });
    }

    pub fn reset(this: Fence, device: Device) anyerror!void {
        return call(device, @src(), "Fence", .{ this, device });
    }

    pub const WaitForEnum = enum { single, all };

    pub fn waitMany(these: []const Fence, device: Device, how_many: WaitForEnum, timeout_ns: ?u64) anyerror!void {
        return call(device, @src(), "Fence", .{ these, device, how_many, timeout_ns });
    }

    pub fn wait(this: Fence, device: Device, timeout_ns: ?u64) anyerror!void {
        try waitMany(&.{this}, device, .all, timeout_ns);
    }

    pub fn checkSignaled(this: Fence, device: Device) bool {
        return call(device, @src(), "Fence", .{ this, device });
    }
};

pub const ResourceSet = union {
    vk: vk.ResourceSet.Handle,

    pub fn init(device: Device, layout: Layout, alloc: std.mem.Allocator) anyerror!ResourceSet {
        return call(device, @src(), "ResourceSet", .{ device, layout, alloc });
    }

    pub fn deinit(this: ResourceSet, device: Device, alloc: std.mem.Allocator) void {
        return call(device, @src(), "ResourceSet", .{ this, device, alloc });
    }

    pub const Write = struct {
        binding: u32,
        data: union(Type) {
            uniform: []const Buffer.Region,
        },
    };

    pub fn update(this: ResourceSet, device: Device, writes: []const Write, alloc: std.mem.Allocator) anyerror!void {
        return call(device, @src(), "ResourceSet", .{ this, device, writes, alloc });
    }

    pub const Type = enum {
        uniform,
        // image,
    };

    pub const Layout = union {
        vk: vk.ResourceSet.Layout.Handle,

        pub const Descriptor = struct {
            t: Type,
            stage: Shader.StageFlags,
            binding: u32,
            count: u32,
        };

        pub const CreateInfo = struct {
            alloc: std.mem.Allocator,
            descriptors: []const Descriptor,
        };

        pub fn init(device: Device, info: CreateInfo) anyerror!Layout {
            return call(device, @src(), .{ "ResourceSet", "Layout" }, .{ device, info });
        }

        pub fn deinit(this: @This(), device: Device, alloc: std.mem.Allocator) void {
            return call(device, @src(), .{ "ResourceSet", "Layout" }, .{ this, device, alloc });
        }
    };
};

pub const Buffer = union {
    vk: vk.Buffer.Handle,

    pub const Location = enum {
        host,
        device,
    };

    pub const Usage = packed struct {
        const BackingInt = @typeInfo(@TypeOf(@This())).@"struct".backing_integer.?;
        const all: Usage = @bitCast(std.math.maxInt(BackingInt));

        src: bool = false,
        dst: bool = false,
        vertex: bool = false,
        index: bool = false,
        uniform: bool = false,
    };

    pub const CreateInfo = struct {
        alloc: std.mem.Allocator,
        loc: Location,
        usage: Usage,
        size: Size,
    };

    pub fn init(device: Device, info: CreateInfo) anyerror!Buffer {
        return call(device, @src(), "Buffer", .{ device, info });
    }

    pub fn deinit(this: Buffer, device: Device, alloc: std.mem.Allocator) void {
        return call(device, @src(), "Buffer", .{ this, device, alloc });
    }

    pub fn map(this: Buffer, device: Device) ![]u8 {
        return this.region().map(device);
    }

    pub fn unmap(this: Buffer, device: Device) void {
        this.region().unmap(device);
    }

    pub fn size(this: Buffer, device: Device) Size {
        return call(device, @src(), "Buffer", .{ this, device });
    }

    pub fn region(this: Buffer) Region {
        return .{
            .buffer = this,
            .offset = 0,
            .size_or_whole = .whole,
        };
    }

    pub const Region = struct {
        buffer: Buffer,
        offset: Size,
        size_or_whole: SizeOrWhole,

        pub fn map(this: Region, device: Device) anyerror![]u8 {
            return call(device, @src(), .{ "Buffer", "Region" }, .{ this, device });
        }

        pub fn unmap(this: Region, device: Device) void {
            return call(device, @src(), .{ "Buffer", "Region" }, .{ this, device });
        }

        pub fn size(this: Region, device: Device) Size {
            return switch (this.size_or_whole) {
                .size => |x| x,
                .whole => this.buffer.size(device),
            };
        }
    };
};

pub const Image = union {
    vk: vk.Image.Handle,

    pub const View = union {
        vk: vk.Image.View.Handle,
    };

    pub const Format = enum {
        bgra8_srgb,
        unknown,
    };

    pub const Layout = enum {
        undefined,
        color_attachment,
        present_src,
    };
};

pub const CommandEncoder = union {
    vk: vk.CommandEncoder.Handle,

    pub fn init(device: Device) anyerror!CommandEncoder {
        return call(device, @src(), "CommandEncoder", .{device});
    }

    pub fn deinit(this: CommandEncoder, device: Device) void {
        return call(device, @src(), "CommandEncoder", .{ this, device });
    }

    pub fn begin(this: CommandEncoder, device: Device) anyerror!void {
        return call(device, @src(), "CommandEncoder", .{ this, device });
    }

    pub fn end(this: CommandEncoder, device: Device) anyerror!void {
        return call(device, @src(), "CommandEncoder", .{ this, device });
    }

    pub fn submit(this: CommandEncoder, device: Device, wait_semaphores: []const Semaphore, signal_semaphores: []const Semaphore, signal_fence: ?Fence) anyerror!void {
        return call(device, @src(), "CommandEncoder", .{ this, device, wait_semaphores, signal_semaphores, signal_fence });
    }

    pub fn cmdCopyBuffer(this: CommandEncoder, device: Device, src: Buffer.Region, dst: Buffer.Region) void {
        return call(device, @src(), "CommandEncoder", .{ this, device, src, dst });
    }

    pub const Stage = packed struct {
        pipeline_start: bool = false,
        pipeline_end: bool = false,
        color_attachment_output: bool = false,
        transfer: bool = false,
        vertex_shader: bool = false,
    };

    pub const Access = packed struct {
        color_attachment_write: bool = false,
        transfer_write: bool = false,
        uniform_read: bool = false,
    };

    pub const MemoryBarrier = union(enum) {
        image: struct {
            image: Image,
            old_layout: Image.Layout,
            new_layout: Image.Layout,
            src_stage: Stage,
            dst_stage: Stage,
            src_access: Access,
            dst_access: Access,
        },
        buffer: struct {
            region: Buffer.Region,
            src_stage: Stage,
            dst_stage: Stage,
            src_access: Access,
            dst_access: Access,
        },
    };

    pub fn cmdMemoryBarrier(this: CommandEncoder, device: Device, memory_barriers: []const MemoryBarrier) void {
        return call(device, @src(), "CommandEncoder", .{ this, device, memory_barriers });
    }

    pub const cmdBeginRenderPass = RenderPassEncoder.cmdBegin;
};

pub const RenderPassEncoder = union {
    vk: vk.RenderPassEncoder.Handle,

    pub const BeginInfo = struct {
        device: Device,
        target: RenderTarget,
        image_size: @Vector(2, u32),
    };

    pub fn cmdBegin(command_encoder: CommandEncoder, info: BeginInfo) RenderPassEncoder {
        return call(info.device, @src(), "RenderPassEncoder", .{ command_encoder, info });
    }

    pub fn cmdEnd(this: RenderPassEncoder, device: Device) void {
        return call(device, @src(), "RenderPassEncoder", .{ this, device });
    }

    pub fn cmdBindPipeline(this: RenderPassEncoder, device: Device, graphics_pipeline: GraphicsPipeline, image_size: @Vector(2, u32)) void {
        return call(device, @src(), "RenderPassEncoder", .{ this, device, graphics_pipeline, image_size });
    }

    pub fn cmdBindVertexBuffer(this: RenderPassEncoder, device: Device, buffer_region: Buffer.Region) void {
        return call(device, @src(), "RenderPassEncoder", .{ this, device, buffer_region });
    }

    pub const IndexType = enum {
        uint16,
        uint32,
    };

    pub fn cmdBindIndexBuffer(this: RenderPassEncoder, device: Device, buffer_region: Buffer.Region, index_type: IndexType) void {
        return call(device, @src(), "RenderPassEncoder", .{ this, device, buffer_region, index_type });
    }

    pub fn cmdBindResourceSets(this: RenderPassEncoder, device: Device, pipeline: GraphicsPipeline, resource_sets: []const ResourceSet, first: u32) void {
        return call(device, @src(), "RenderPassEncoder", .{ this, device, pipeline, resource_sets, first });
    }

    pub const DrawInfo = struct {
        device: Device,
        vertex_count: u32,
        indexed: bool,
    };

    pub fn cmdDraw(this: RenderPassEncoder, info: DrawInfo) void {
        return call(info.device, @src(), "RenderPassEncoder", .{ this, info });
    }
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
