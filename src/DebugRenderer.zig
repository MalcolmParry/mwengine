const std = @import("std");
const gpu = @import("gpu.zig");
const math = @import("math.zig");

const DebugRenderer = @This();

alloc: std.mem.Allocator,
device: gpu.Device,
stage_man: *gpu.StagingManager,
upload_man: gpu.UploadManager,
frame_index: usize,
frames_in_flight: usize,
vbuffer: gpu.Buffer,
vbuffer_offset: gpu.Size,
vbuffer_size: usize,
line_pipeline: gpu.GraphicsPipeline,
viewport: gpu.Image.Size2D = @splat(1),

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
            .rate = .per_vertex,
            .fields = &.{.{ .type = .float32x2 }},
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
        .upload_man = .{
            .alloc = info.alloc,
            .stage_man = info.stage_man,
        },
        .frame_index = 0,
        .frames_in_flight = info.frames_in_flight,
        .vbuffer = vbuffer,
        .vbuffer_offset = 0,
        .vbuffer_size = info.vbuffer_size,

        .line_pipeline = line_pipeline,
    };
}

pub fn deinit(renderer: *DebugRenderer) void {
    renderer.line_pipeline.deinit(renderer.device, renderer.alloc);
    renderer.vbuffer.deinit(renderer.device, renderer.alloc);
    renderer.upload_man.deinit();
}

pub fn render(renderer: *DebugRenderer, cmd_encoder: gpu.CommandEncoder, target: gpu.RenderTarget, image_size: gpu.Image.Size2D) !void {
    try renderer.upload_man.upload(renderer.device, cmd_encoder);

    const render_pass = cmd_encoder.cmdBeginRenderPass(.{
        .device = renderer.device,
        .target = target,
        .image_size = image_size,
    });

    render_pass.cmdBindPipeline(renderer.device, renderer.line_pipeline, image_size);
    render_pass.cmdBindVertexBuffer(renderer.device, 0, .{
        .buffer = renderer.vbuffer,
        .offset = renderer.vbufferOffsetBase(),
        .size_or_whole = .{ .size = renderer.vbuffer_offset },
    });
    render_pass.cmdDraw(.{
        .device = renderer.device,
        .indexed = false,
        .vertex_count = @intCast(renderer.vbuffer_offset / @sizeOf(Vertex)),
    });

    render_pass.cmdEnd(renderer.device);
}

pub fn nextFrame(renderer: *DebugRenderer) void {
    renderer.vbuffer_offset = 0;
    renderer.frame_index = (renderer.frame_index + 1) % renderer.frames_in_flight;
}

fn toDeviceCoords(renderer: *DebugRenderer, vec: math.Vec2) math.Vec2 {
    var new = vec;
    new /= @as(math.Vec2, @floatFromInt(renderer.viewport));
    new *= @as(math.Vec2, @splat(2));
    new -= @as(math.Vec2, @splat(1));
    new[1] *= -1;
    return new;
}

pub fn drawLine(renderer: *DebugRenderer, start: math.Vec2, end: math.Vec2, thickness: f32) !void {
    const to = end - start;
    const len = math.length(to);
    if (len == 0) return;

    const n = to / @as(math.Vec2, @splat(len));
    const thick_vec: math.Vec2 = @splat(thickness / 2);
    const right = math.Vec2{
        n[1],
        -n[0],
    } * thick_vec;

    const br = renderer.toDeviceCoords(start + right);
    const bl = renderer.toDeviceCoords(start - right);
    const tr = renderer.toDeviceCoords(end + right);
    const tl = renderer.toDeviceCoords(end - right);

    const vertices: [6]Vertex = .{
        .{ .pos = bl },
        .{ .pos = br },
        .{ .pos = tl },

        .{ .pos = br },
        .{ .pos = tr },
        .{ .pos = tl },
    };

    const size = @sizeOf(Vertex) * 6;
    const region: gpu.Buffer.Region = .{
        .buffer = renderer.vbuffer,
        .offset = renderer.vbufferOffsetBase() + renderer.vbuffer_offset,
        .size_or_whole = .{ .size = size },
    };
    renderer.vbuffer_offset += size;
    if (renderer.vbuffer_offset > renderer.vbuffer_size) return error.BufferFull;

    try renderer.upload_man.submit([6]Vertex, .{
        .region = region,
        .data = @ptrCast(&vertices),
        .post_copy_barrier = .{ .buffer = .{
            .region = region,
            .src_stage = .{ .transfer = true },
            .src_access = .{ .transfer_write = true },
            .dst_stage = .{ .vertex_input = true },
            .dst_access = .{ .vertex_read = true },
        } },
    });
}

fn vbufferOffsetBase(renderer: *DebugRenderer) gpu.Size {
    return renderer.vbuffer_size * renderer.frame_index;
}

const Vertex = extern struct {
    pos: [2]f32,
};
