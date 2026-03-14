const std = @import("std");
const gpu = @import("gpu.zig");
const math = @import("math.zig");

const DebugRenderer = @This();

alloc: std.mem.Allocator,
device: gpu.Device,
stage_man: *gpu.StagingManager,
frame_index: usize,
frames_in_flight: usize,
vbuffer: gpu.Buffer,
line_pipeline: gpu.GraphicsPipeline,
lines: std.ArrayList(GPULine),

pub const InitInfo = struct {
    alloc: std.mem.Allocator,
    device: gpu.Device,
    stage_man: *gpu.StagingManager,
    frames_in_flight: usize,
    vbuffer_size: usize = 1024 * 8,
    line_shaders: []const gpu.Shader,
    render_target_desc: gpu.RenderTarget.Desc,
};

pub fn init(info: InitInfo) !DebugRenderer {
    const vbuffer = try info.device.initBuffer(.{
        .alloc = info.alloc,
        .size = info.vbuffer_size * info.frames_in_flight,
        .loc = .device,
        .usage = .{ .vertex = true, .dst = true },
    });
    errdefer vbuffer.deinit(info.device, info.alloc);

    const line_pipeline = try info.device.initGraphicsPipeline(.{
        .alloc = info.alloc,
        .render_target_desc = info.render_target_desc,
        .shaders = info.line_shaders,
        .vertex_input_bindings = &.{.{
            .binding = 0,
            .rate = .per_instance,
            .fields = &.{
                .{ .type = .float32x2 },
                .{ .type = .snorm16x2 },
                .{ .type = .float16 },
                .{ .type = .float16 },
            },
        }},
        .push_constant_ranges = &.{.{
            .size = @sizeOf(f32) * 4 * 4,
            .offset = 0,
            .stages = .{ .vertex = true },
        }},
        .polygon_mode = .fill,
        .cull_mode = .none,
        .depth_mode = .{
            .testing = false,
            .writing = false,
            .compare_op = .always,
        },
    });
    errdefer line_pipeline.deinit(info.device, info.alloc);

    return .{
        .alloc = info.alloc,
        .device = info.device,
        .stage_man = info.stage_man,
        .frame_index = 0,
        .frames_in_flight = info.frames_in_flight,
        .vbuffer = vbuffer,

        .line_pipeline = line_pipeline,
        .lines = .empty,
    };
}

pub fn deinit(renderer: *DebugRenderer) void {
    renderer.line_pipeline.deinit(renderer.device, renderer.alloc);
    renderer.vbuffer.deinit(renderer.device, renderer.alloc);
    renderer.lines.deinit(renderer.alloc);
}

pub fn render(renderer: *DebugRenderer, cmd_encoder: gpu.CommandEncoder, target: gpu.RenderTarget, image_size: gpu.Image.Size2D, matrix: math.Mat4) !void {
    const vbuffer_base_offset = renderer.vbufferOffsetBase();
    const vbuffer_size_pf = renderer.vbufferSizePerFrame();

    const line_bytes = renderer.lines.items.len * @sizeOf(GPULine);
    if (line_bytes > vbuffer_size_pf) return error.OutOfDeviceMemory;

    const line_staging = try renderer.stage_man.allocate(GPULine, renderer.lines.items.len);
    @memcpy(line_staging.slice, renderer.lines.items);
    const line_region: gpu.Buffer.Region = .{
        .buffer = renderer.vbuffer,
        .offset = vbuffer_base_offset,
        .size_or_whole = .{ .size = line_bytes },
    };

    cmd_encoder.cmdCopyBuffer(renderer.device, line_staging.region, line_region);
    try cmd_encoder.cmdMemoryBarrier(renderer.device, &.{.{ .buffer = .{
        .region = line_region,
        .src_stage = .{ .transfer = true },
        .src_access = .{ .transfer_write = true },
        .dst_stage = .{ .vertex_input = true },
        .dst_access = .{ .vertex_read = true },
    } }}, renderer.alloc);

    const render_pass = cmd_encoder.cmdBeginRenderPass(.{
        .device = renderer.device,
        .target = target,
        .image_size = image_size,
    });

    render_pass.cmdBindPipeline(renderer.device, renderer.line_pipeline, image_size);
    render_pass.cmdBindVertexBuffer(renderer.device, 0, line_region);
    render_pass.cmdPushConstants(
        renderer.device,
        renderer.line_pipeline,
        .{
            .size = @sizeOf(f32) * 4 * 4,
            .offset = 0,
            .stages = .{ .vertex = true },
        },
        @ptrCast(&math.toArray(matrix)),
    );
    render_pass.cmdDraw(.{
        .device = renderer.device,
        .indexed = false,
        .vertex_count = 6,
        .instance_count = @intCast(renderer.lines.items.len),
    });

    render_pass.cmdEnd(renderer.device);
}

pub fn nextFrame(renderer: *DebugRenderer) void {
    renderer.frame_index = (renderer.frame_index + 1) % renderer.frames_in_flight;
    renderer.lines.clearRetainingCapacity();
}

pub fn drawLine(renderer: *DebugRenderer, start: math.Vec2, end: math.Vec2, thickness: f16) !void {
    if (@reduce(.And, start == end)) return;

    const to = end - start;
    const len = math.length(to);
    const norm = to / math.splat2(f32, len);

    try renderer.lines.append(renderer.alloc, .{
        .pos = start,
        .dir = .{
            math.f32ToSNorm16(norm[0]),
            math.f32ToSNorm16(norm[1]),
        },
        .length = @floatCast(len),
        .width = thickness,
    });
}

pub fn drawBezier(renderer: *@This(), a: math.Vec2, b: math.Vec2, c: math.Vec2, thickness: f16, res: u32) !void {
    const step = 1.0 / @as(f32, @floatFromInt(res));

    var last = a;
    for (1..res + 1) |i| {
        const fi: f32 = @floatFromInt(i);
        const t = fi * step;

        const next = math.lerp(
            math.Vec2,
            math.lerp(math.Vec2, a, b, t),
            math.lerp(math.Vec2, b, c, t),
            t,
        );

        try renderer.drawLine(last, next, thickness);
        last = next;
    }
}

fn vbufferSizePerFrame(renderer: *const DebugRenderer) gpu.Size {
    return renderer.vbuffer.size(renderer.device) / renderer.frames_in_flight;
}

fn vbufferOffsetBase(renderer: *const DebugRenderer) gpu.Size {
    return renderer.vbufferSizePerFrame() * renderer.frame_index;
}

const GPULine = extern struct {
    pos: [2]f32,
    dir: [2]math.SNorm16,
    length: f16,
    width: f16,
};
