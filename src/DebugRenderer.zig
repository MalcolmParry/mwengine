const std = @import("std");
const gpu = @import("gpu.zig");
const math = @import("math.zig");

const DebugRenderer = @This();

alloc: std.mem.Allocator,
device: gpu.Device,
stage_man: *gpu.StagingManager,
frame_index: usize,
pf: []PerFrame,
vbuffer: gpu.Buffer,
line_pipeline: gpu.GraphicsPipeline,
line_draws: std.ArrayList(GpuLine),

image_sampler: gpu.Sampler,
image_resource_layout: gpu.ResourceSet.Layout,
image_pipeline: gpu.GraphicsPipeline,
image_draws: std.ArrayList(GpuImage),
images: std.ArrayHashMapUnmanaged(gpu.ResourceSet.CombinedImageSampler, void, ImageHashContext, false),

const ImageHashContext = struct {
    api: gpu.Api,

    const Key = gpu.ResourceSet.CombinedImageSampler;
    pub fn hash(ctx: ImageHashContext, key: Key) u32 {
        return @truncate(ctx.api.hashBy(key.view));
    }

    pub fn eql(ctx: ImageHashContext, a: Key, b: Key, _: usize) bool {
        return ctx.api.eqlBy(a.view, b.view);
    }
};

const max_images = 64;

pub const InitInfo = struct {
    alloc: std.mem.Allocator,
    device: gpu.Device,
    stage_man: *gpu.StagingManager,
    frames_in_flight: usize,
    vbuffer_size: usize = 1024 * 8,
    line_shaders: []const gpu.Shader,
    image_shaders: []const gpu.Shader,
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

    const image_sampler = try info.device.initSampler(.{
        .alloc = info.alloc,
        .min_filter = .linear,
        .mag_filter = .nearest,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
    });
    errdefer image_sampler.deinit(info.device, info.alloc);

    const image_resource_layout = try info.device.initResourceLayout(.{
        .alloc = info.alloc,
        .descriptors = &.{.{
            .t = .image,
            .stages = .{ .pixel = true },
            .flags = .{ .partially_bound = true },
            .binding = 0,
            .count = max_images,
        }},
    });
    errdefer image_resource_layout.deinit(info.device, info.alloc);

    const image_pipeline = try info.device.initGraphicsPipeline(.{
        .alloc = info.alloc,
        .render_target_desc = info.render_target_desc,
        .shaders = info.image_shaders,
        .vertex_input_bindings = &.{.{
            .binding = 0,
            .rate = .per_instance,
            .fields = &.{
                .{ .type = .float32x3x3 },
                .{ .type = .uint32 },
            },
        }},
        .resource_layouts = &.{image_resource_layout},
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
    errdefer image_pipeline.deinit(info.device, info.alloc);

    const pf = try info.alloc.alloc(PerFrame, info.frames_in_flight);
    errdefer info.alloc.free(pf);

    var init_count: usize = 0;
    errdefer for (pf[0..init_count]) |*x| x.image_resource_set.deinit(info.device, info.alloc);
    for (pf) |*x| {
        x.image_resource_set = try info.device.initResourceSet(image_resource_layout, info.alloc);
        init_count += 1;
    }

    return .{
        .alloc = info.alloc,
        .device = info.device,
        .stage_man = info.stage_man,
        .frame_index = 0,
        .pf = pf,
        .vbuffer = vbuffer,

        .line_pipeline = line_pipeline,
        .line_draws = .empty,

        .image_sampler = image_sampler,
        .image_resource_layout = image_resource_layout,
        .image_pipeline = image_pipeline,
        .image_draws = .empty,
        .images = .empty,
    };
}

pub fn deinit(renderer: *DebugRenderer) void {
    for (renderer.pf) |*x| x.image_resource_set.deinit(renderer.device, renderer.alloc);
    renderer.alloc.free(renderer.pf);

    renderer.line_pipeline.deinit(renderer.device, renderer.alloc);
    renderer.vbuffer.deinit(renderer.device, renderer.alloc);
    renderer.line_draws.deinit(renderer.alloc);

    renderer.image_sampler.deinit(renderer.device, renderer.alloc);
    renderer.image_pipeline.deinit(renderer.device, renderer.alloc);
    renderer.image_resource_layout.deinit(renderer.device, renderer.alloc);
    renderer.image_draws.deinit(renderer.alloc);
    renderer.images.deinit(renderer.alloc);
}

pub fn render(renderer: *DebugRenderer, cmd_encoder: gpu.CommandEncoder, target: gpu.RenderTarget, image_size: gpu.Image.Size2D, matrix: math.Mat4) !void {
    const vbuffer_base_offset = renderer.vbufferOffsetBase();
    const vbuffer_size_pf = renderer.vbufferSizePerFrame();

    const line_bytes = renderer.line_draws.items.len * @sizeOf(GpuLine);
    if (line_bytes > vbuffer_size_pf) return error.BufferFull;
    const line_region: gpu.Buffer.Region = .{
        .buffer = renderer.vbuffer,
        .offset = vbuffer_base_offset,
        .size_or_whole = .{ .size = line_bytes },
    };

    const images_offset = line_bytes;
    const images_bytes = renderer.image_draws.items.len * @sizeOf(GpuImage);
    if (images_offset + images_bytes > vbuffer_size_pf) return error.BufferFull;
    const images_region: gpu.Buffer.Region = .{
        .buffer = renderer.vbuffer,
        .offset = vbuffer_base_offset + line_bytes,
        .size_or_whole = .{ .size = images_bytes },
    };

    const all_bytes = line_bytes + images_bytes;
    const staging = try renderer.stage_man.allocateBytesAligned(all_bytes, .@"16");
    const region: gpu.Buffer.Region = .{
        .buffer = renderer.vbuffer,
        .offset = vbuffer_base_offset,
        .size_or_whole = .{ .size = all_bytes },
    };

    @memcpy(staging.slice[0..line_bytes], std.mem.sliceAsBytes(renderer.line_draws.items));
    @memcpy(staging.slice[line_bytes .. line_bytes + images_bytes], std.mem.sliceAsBytes(renderer.image_draws.items));

    cmd_encoder.cmdCopyBuffer(staging.region, region);
    try cmd_encoder.cmdMemoryBarrier(&.{.{ .buffer = .{
        .region = region,
        .src_stage = .{ .transfer = true },
        .src_access = .{ .transfer_write = true },
        .dst_stage = .{ .vertex_input = true },
        .dst_access = .{ .vertex_read = true },
    } }}, renderer.alloc);

    const render_pass = cmd_encoder.cmdBeginRenderPass(.{
        .target = target,
        .image_size = image_size,
    });

    try renderer.renderLines(render_pass, image_size, matrix, line_region);
    try renderer.renderImages(render_pass, image_size, matrix, images_region);

    render_pass.cmdEnd();
}

fn renderLines(renderer: *DebugRenderer, render_pass: gpu.RenderPassEncoder, image_size: gpu.Image.Size2D, matrix: math.Mat4, vertex_input: gpu.Buffer.Region) !void {
    if (vertex_input.size_or_whole.size == 0) return;

    render_pass.cmdBindPipeline(renderer.line_pipeline, image_size);
    render_pass.cmdPushConstants(
        renderer.line_pipeline,
        .{
            .size = @sizeOf(f32) * 4 * 4,
            .offset = 0,
            .stages = .{ .vertex = true },
        },
        @ptrCast(&math.toArray(matrix)),
    );
    render_pass.cmdBindVertexBuffer(0, vertex_input);
    render_pass.cmdDraw(.{
        .indexed = false,
        .vertex_count = 6,
        .instance_count = @intCast(vertex_input.size_or_whole.size / @sizeOf(GpuLine)),
    });
}

fn renderImages(renderer: *DebugRenderer, render_pass: gpu.RenderPassEncoder, image_size: gpu.Image.Size2D, matrix: math.Mat4, vertex_input: gpu.Buffer.Region) !void {
    if (vertex_input.size_or_whole.size == 0) return;

    const resource_set = renderer.pf[renderer.frame_index].image_resource_set;
    try resource_set.update(renderer.device, &.{.{
        .binding = 0,
        .data = .{ .image = renderer.images.keys() },
    }}, renderer.alloc);

    render_pass.cmdBindPipeline(renderer.image_pipeline, image_size);
    render_pass.cmdPushConstants(
        renderer.image_pipeline,
        .{
            .size = @sizeOf(f32) * 4 * 4,
            .offset = 0,
            .stages = .{ .vertex = true },
        },
        @ptrCast(&math.toArray(matrix)),
    );
    render_pass.cmdBindVertexBuffer(0, vertex_input);
    render_pass.cmdBindResourceSets(renderer.image_pipeline, &.{resource_set}, 0);
    render_pass.cmdDraw(.{
        .indexed = false,
        .vertex_count = 6,
        .instance_count = @intCast(vertex_input.size_or_whole.size / @sizeOf(GpuImage)),
    });
}

pub fn nextFrame(renderer: *DebugRenderer) void {
    renderer.frame_index = (renderer.frame_index + 1) % renderer.pf.len;
    renderer.line_draws.clearRetainingCapacity();
    renderer.image_draws.clearRetainingCapacity();
    renderer.images.clearRetainingCapacity();
}

pub fn drawLine(renderer: *DebugRenderer, start: math.Vec2, end: math.Vec2, thickness: f16) !void {
    if (@reduce(.And, start == end)) return;

    const to = end - start;
    const len = math.length(to);
    const norm = to / math.splat2(f32, len);

    try renderer.line_draws.append(renderer.alloc, .{
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

pub fn drawImage(renderer: *@This(), view: gpu.Image.View, mat: math.Mat3) !void {
    const key: gpu.ResourceSet.CombinedImageSampler = .{
        .layout = .shader_read_only,
        .view = view,
        .sampler = renderer.image_sampler,
    };

    try renderer.images.putContext(renderer.alloc, key, {}, .{ .api = renderer.device });
    const index = renderer.images.getIndex(key).?;
    if (index >= max_images) {
        renderer.images.orderedRemoveAt(index);
        return error.TooManyImages;
    }

    try renderer.image_draws.append(renderer.alloc, .{
        .mat = math.toArray(mat),
        .id = @intCast(index),
    });
}

fn vbufferSizePerFrame(renderer: *const DebugRenderer) gpu.Size {
    return renderer.vbuffer.size(renderer.device) / renderer.pf.len;
}

fn vbufferOffsetBase(renderer: *const DebugRenderer) gpu.Size {
    return renderer.vbufferSizePerFrame() * renderer.frame_index;
}

const GpuLine = extern struct {
    pos: [2]f32,
    dir: [2]math.SNorm16,
    length: f16,
    width: f16,
};

const GpuImage = extern struct {
    mat: [3 * 3]f32,
    id: u32,
};

const PerFrame = struct {
    image_resource_set: gpu.ResourceSet,
};
