const std = @import("std");
const gpu = @import("../gpu/gpu.zig");
const math = @import("../math.zig");
const Immediate = @This();

alloc: std.mem.Allocator,
stream_alloc: gpu.PushAllocator,
staging: gpu.Buffer,
stage_mapping: []u8,
box_renderer: ?BoxRenderer,
frame_data: ?FrameData,

pub const InitInfo = struct {
    alloc: std.mem.Allocator,
    device: gpu.Device,
    frames_in_flight: u32,
    streaming_buffer_size_pf: gpu.Size,
    color_format: gpu.Image.Format,
    box_info: ?BoxRenderer.InitInfo = null,
};

pub fn init(info: InitInfo) !Immediate {
    const buffer_size = info.streaming_buffer_size_pf * info.frames_in_flight;
    const streaming_buffer = try info.device.initBuffer(.{
        .alloc = info.alloc,
        .loc = .device,
        .usage = .{ .dst = true, .vertex = true },
        .size = buffer_size,
    });
    errdefer streaming_buffer.deinit(info.device, info.alloc);

    const staging = try info.device.initBuffer(.{
        .alloc = info.alloc,
        .loc = .host,
        .usage = .{ .src = true },
        .size = buffer_size,
    });
    errdefer staging.deinit(info.device, info.alloc);
    const stage_mapping = try staging.map(info.device);

    var immediate: Immediate = .{
        .alloc = info.alloc,
        .stream_alloc = .{
            .buffer = streaming_buffer,
            .frames_in_flight = info.frames_in_flight,
            .size_pf = info.streaming_buffer_size_pf,
        },
        .staging = staging,
        .stage_mapping = stage_mapping,
        .box_renderer = null,
        .frame_data = null,
    };

    if (info.box_info) |_|
        try BoxRenderer.init(&immediate, info);
    errdefer if (info.box_info) |_|
        BoxRenderer.deinit(&immediate, info.device);

    return immediate;
}

pub fn deinit(immediate: *Immediate, device: gpu.Device) void {
    if (immediate.box_renderer) |_|
        BoxRenderer.deinit(immediate, device);

    immediate.stream_alloc.buffer.deinit(device, immediate.alloc);
    immediate.staging.deinit(device, immediate.alloc);
}

pub const DrawRectInfo = struct {
    transform: Transform,
    color: [4]u8,
};

pub fn begin(immediate: *Immediate, image_size: [2]u16) !void {
    if (immediate.box_renderer) |*x| {
        x.vertex_data.clearRetainingCapacity();
    }

    immediate.stream_alloc.nextFrame();
    immediate.frame_data = .{
        .image_size = image_size,
    };
}

pub fn render(immediate: *Immediate, cmd_encoder: gpu.CommandEncoder, image_view: gpu.Image.View) !void {
    if (immediate.box_renderer) |_| try BoxRenderer.upload(immediate);

    const region = immediate.stream_alloc.usedRegion();
    const staging: gpu.Buffer.Region = .{
        .buffer = immediate.staging,
        .offset = region.offset,
        .size = region.size,
    };

    if (region.size == 0) return;
    cmd_encoder.cmdCopyBuffer(staging, region);
    cmd_encoder.cmdMemoryBarrier(.{ .buffer_barriers = &.{.{
        .region = region,
        .src_stage = .{ .transfer = true },
        .src_access = .{ .transfer_write = true },
        .dst_stage = .{ .vertex_input = true },
        .dst_access = .{ .vertex_read = true },
    }} });

    const render_pass = cmd_encoder.cmdBeginRenderPass(.{
        .target = .{
            .color_attachment = .{
                .image_view = image_view,
                .load = .load,
                .store = .store,
            },
        },
        .image_size = immediate.frame_data.?.image_size,
    });

    const pc: PushConstants = .{
        .image_size = @as(math.Vec2, @floatFromInt(@as(@Vector(2, u16), immediate.frame_data.?.image_size))),
    };

    if (immediate.box_renderer) |_| try BoxRenderer.render(immediate, render_pass, pc);

    render_pass.cmdEnd();
}

pub fn drawRect(immediate: *Immediate, info: DrawRectInfo) !void {
    const image_size = immediate.frame_data.?.image_size;

    const half: math.Vec2 = @splat(0.5);
    const pivot: math.Vec2 = info.transform.pivot;
    const s_pivot = (pivot - half) / half;

    try immediate.box_renderer.?.vertex_data.append(immediate.alloc, .{
        .pos = info.transform.pos.pixels(image_size),
        .size = info.transform.size.pixels(image_size),
        .cos = math.normFromFloat(i16, @cos(info.transform.angle)),
        .sin = math.normFromFloat(i16, @sin(info.transform.angle)),
        .pivot = .{
            math.normFromFloat(i16, s_pivot[0]),
            math.normFromFloat(i16, s_pivot[1]),
        },
        .color = info.color,
    });
}

pub const NormWithOffset = struct {
    /// bottom left = (0, 0), top right = (1, 1)
    norm: [2]f32,
    /// offset in pixels
    offset: [2]i16,

    const u16x2 = @Vector(2, u16);
    const i16x2 = @Vector(2, i16);
    pub fn pixels(this: NormWithOffset, image_size: [2]u16) [2]i16 {
        const f_image_size: math.Vec2 = @floatFromInt(@as(u16x2, image_size));
        const from_norm = @as(math.Vec2, this.norm) * f_image_size;
        const i_from_norm: i16x2 = @intFromFloat(from_norm);
        return @as(i16x2, i_from_norm + this.offset);
    }
};

pub const Transform = struct {
    pos: NormWithOffset,
    size: NormWithOffset,
    /// angle in radians
    angle: f32 = 0,
    /// coords relative to shape
    /// bottom left = (0, 0), top right = (1, 1)
    pivot: [2]f32 = @splat(0),
};

const FrameData = struct {
    image_size: [2]u16,
};

const BoxRenderer = struct {
    pipeline: gpu.GraphicsPipeline,
    vertex_data: std.ArrayList(VertexInput),
    vertex_buffer_offset: gpu.Size = std.math.maxInt(gpu.Size),

    const InitInfo = struct {
        shaders: []const gpu.Shader,
    };

    fn init(immediate: *Immediate, info: Immediate.InitInfo) !void {
        const pipeline = try info.device.initGraphicsPipeline(.{
            .alloc = info.alloc,
            .render_target_desc = .{
                .color_format = info.color_format,
                .depth_format = null,
            },
            .shaders = info.box_info.?.shaders,
            .vertex_input_bindings = &.{.{
                .binding = 0,
                .rate = .per_instance,
                .fields = &.{
                    // pos and size
                    .{ .type = .sint16x4 },
                    // cos a, sin a, pivot
                    .{ .type = .snorm16x4 },
                    // color
                    .{ .type = .unorm8x4 },
                },
            }},
            .push_constant_ranges = &.{.{
                .size = @sizeOf(PushConstants),
                .offset = 0,
                .stages = .{ .vertex = true },
            }},
            .blend_info = .{
                .src_color_factor = .src_alpha,
                .dst_color_factor = .one_minus_src_alpha,
                .color_op = .add,
                .src_alpha_factor = .one,
                .dst_alpha_factor = .one,
                .alpha_op = .max,
            },
        });
        errdefer pipeline.deinit(info.device, info.alloc);

        immediate.box_renderer = .{
            .pipeline = pipeline,
            .vertex_data = .empty,
        };
    }

    fn deinit(immediate: *Immediate, device: gpu.Device) void {
        const this = &immediate.box_renderer.?;

        this.vertex_data.deinit(immediate.alloc);
        this.pipeline.deinit(device, immediate.alloc);
    }

    fn upload(immediate: *Immediate) !void {
        const this = &immediate.box_renderer.?;
        const data = this.vertex_data.items;
        if (data.len == 0) return;

        const region = try immediate.stream_alloc.allocTAligned(VertexInput, data.len, .@"4");
        const staging = immediate.stage_mapping[region.offset..][0..region.size];

        @memcpy(staging, std.mem.sliceAsBytes(data));
        this.vertex_buffer_offset = region.offset;
    }

    fn render(immediate: *Immediate, render_pass: gpu.RenderPassEncoder, pc: PushConstants) !void {
        const this = &immediate.box_renderer.?;
        const count = this.vertex_data.items.len;
        if (count == 0) return;

        render_pass.cmdBindPipeline(this.pipeline);
        render_pass.cmdPushConstants(this.pipeline, .{
            .offset = 0,
            .size = @sizeOf(PushConstants),
            .stages = .{ .vertex = true },
        }, std.mem.asBytes(&pc));
        render_pass.cmdBindVertexBuffer(0, .{
            .buffer = immediate.stream_alloc.buffer,
            .offset = this.vertex_buffer_offset,
            .size = count * @sizeOf(VertexInput),
        });

        render_pass.cmdDraw(.{
            .vertex_count = 6,
            .instance_count = @intCast(count),
            .indexed = false,
        });
    }

    const VertexInput = extern struct {
        pos: [2]i16,
        size: [2]i16,
        cos: i16,
        sin: i16,
        /// bottom left is (-1, -1) top right is (1, 1)
        pivot: [2]i16,
        color: [4]u8,
    };
};

const PushConstants = extern struct {
    image_size: [2]f32,
};
