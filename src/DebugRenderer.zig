const std = @import("std");
const gpu = @import("gpu.zig");
const math = @import("math.zig");
const text = @import("text.zig");

const DebugRenderer = @This();

alloc: std.mem.Allocator,
device: gpu.Device,
stage_man: *gpu.StagingManager,
push_alloc: gpu.PushAllocator,
frame_index: usize,
pf: []PerFrame,
line_pipeline: gpu.GraphicsPipeline,
line_draws: std.ArrayList(GpuLine),

image_sampler: gpu.Sampler,
image_resource_layout: gpu.ResourceSet.Layout,
image_pipeline: gpu.GraphicsPipeline,
image_draws: std.ArrayList(GpuImage),
images: std.ArrayHashMapUnmanaged(gpu.ResourceSet.CombinedImageSampler, void, ImageHashContext, false),

font_face_loaded: *text.Face.Loaded,

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

const TextDraw = struct {
    atlas: u32,
    mat: math.Mat3,
    baked: []text.Face.Loaded.BakedChar,
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
    text_shaders: []const gpu.Shader,
    render_target_desc: gpu.RenderTarget.Desc,
    font_face_loaded: *text.Face.Loaded,
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
                .{ .type = .unorm16x4 },
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
        .depth_mode = .disabled,
    });
    errdefer image_pipeline.deinit(info.device, info.alloc);

    const pf = try info.alloc.alloc(PerFrame, info.frames_in_flight);
    errdefer info.alloc.free(pf);

    var init_count: usize = 0;
    errdefer for (pf[0..init_count]) |*x|
        x.image_resource_set.deinit(info.device, info.alloc);

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
        .push_alloc = .{
            .buffer = vbuffer,
            .frames_in_flight = @intCast(info.frames_in_flight),
            .size_pf = info.vbuffer_size,
        },

        .line_pipeline = line_pipeline,
        .line_draws = .empty,

        .image_sampler = image_sampler,
        .image_resource_layout = image_resource_layout,
        .image_pipeline = image_pipeline,
        .image_draws = .empty,
        .images = .empty,

        .font_face_loaded = info.font_face_loaded,
    };
}

pub fn deinit(renderer: *DebugRenderer) void {
    for (renderer.pf) |*x| {
        x.image_resource_set.deinit(renderer.device, renderer.alloc);
    }
    renderer.alloc.free(renderer.pf);

    renderer.line_pipeline.deinit(renderer.device, renderer.alloc);
    renderer.push_alloc.buffer.deinit(renderer.device, renderer.alloc);
    renderer.line_draws.deinit(renderer.alloc);

    renderer.image_sampler.deinit(renderer.device, renderer.alloc);
    renderer.image_pipeline.deinit(renderer.device, renderer.alloc);
    renderer.image_resource_layout.deinit(renderer.device, renderer.alloc);
    renderer.image_draws.deinit(renderer.alloc);
    renderer.images.deinit(renderer.alloc);
}

pub fn render(renderer: *DebugRenderer, cmd_encoder: gpu.CommandEncoder, target: gpu.RenderTarget, image_size: gpu.Image.Size2D, matrix: math.Mat4) !void {
    renderer.push_alloc.nextFrame();

    const line_region = try renderer.push_alloc.allocTAligned(GpuLine, renderer.line_draws.items.len, .@"4");

    const image_offset = renderer.push_alloc.offset;
    const image_region = try renderer.push_alloc.allocTAligned(GpuImage, renderer.image_draws.items.len, .@"4");

    const all_bytes = renderer.push_alloc.offset;
    if (all_bytes == 0) return;
    const staging = try renderer.stage_man.allocateBytesAligned(all_bytes, .@"4");
    const full_region = renderer.push_alloc.usedRegion();

    @memcpy(staging.slice[0..line_region.size_or_whole.size], std.mem.sliceAsBytes(renderer.line_draws.items));
    @memcpy(staging.slice[image_offset..][0..image_region.size_or_whole.size], std.mem.sliceAsBytes(renderer.image_draws.items));

    cmd_encoder.cmdCopyBuffer(staging.region, full_region);
    cmd_encoder.cmdMemoryBarrier(.{
        .buffer_barriers = &.{.{
            .region = full_region,
            .src_stage = .{ .transfer = true },
            .src_access = .{ .transfer_write = true },
            .dst_stage = .{ .vertex_input = true },
            .dst_access = .{ .vertex_read = true },
        }},
    });

    const render_pass = cmd_encoder.cmdBeginRenderPass(.{
        .target = target,
        .image_size = image_size,
    });

    try renderer.renderLines(render_pass, matrix, line_region);
    try renderer.renderImages(render_pass, matrix, image_region);

    render_pass.cmdEnd();
}

fn renderLines(renderer: *DebugRenderer, render_pass: gpu.RenderPassEncoder, matrix: math.Mat4, vertex_input: gpu.Buffer.Region) !void {
    if (vertex_input.size_or_whole.size == 0) return;

    render_pass.cmdBindPipeline(renderer.line_pipeline);
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

fn renderImages(renderer: *DebugRenderer, render_pass: gpu.RenderPassEncoder, matrix: math.Mat4, vertex_input: gpu.Buffer.Region) !void {
    if (vertex_input.size_or_whole.size == 0) return;

    const resource_set = renderer.pf[renderer.frame_index].image_resource_set;
    try resource_set.update(renderer.device, &.{.{
        .binding = 0,
        .data = .{ .image = renderer.images.keys() },
    }}, renderer.alloc);

    render_pass.cmdBindPipeline(renderer.image_pipeline);
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

    for (renderer.text_draws.items) |draw| renderer.alloc.free(draw.baked);
    renderer.text_draws.clearRetainingCapacity();
}

pub fn drawLine(renderer: *DebugRenderer, start: math.Vec2, end: math.Vec2, thickness: f16) !void {
    if (@reduce(.And, start == end)) return;

    const to = end - start;
    const len = math.length(to);
    const norm = to / math.splat2(f32, len);

    try renderer.line_draws.append(renderer.alloc, .{
        .pos = start,
        .dir = .{
            math.normFromFloat(i16, norm[0]),
            math.normFromFloat(i16, norm[1]),
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

pub const ImageDrawInfo = struct {
    view: gpu.Image.View,
    mat: math.Mat3,
    uv_top_left: math.Vec2 = @splat(0),
    uv_bottom_right: math.Vec2 = @splat(1),
};

pub fn drawImage(renderer: *@This(), info: ImageDrawInfo) !void {
    const key: gpu.ResourceSet.CombinedImageSampler = .{
        .layout = .shader_read_only,
        .view = info.view,
        .sampler = renderer.image_sampler,
    };

    try renderer.images.putContext(renderer.alloc, key, {}, .{ .api = renderer.device });
    const index = renderer.images.getIndex(key).?;
    if (index >= max_images) {
        renderer.images.orderedRemoveAt(index);
        return error.TooManyImages;
    }

    try renderer.image_draws.append(renderer.alloc, .{
        .mat = math.toArray(info.mat),
        .id = @intCast(index),
        .uv_bounds = .{
            math.normFromFloat(u16, info.uv_top_left[0]),
            math.normFromFloat(u16, 1 - info.uv_top_left[1]),
            math.normFromFloat(u16, info.uv_bottom_right[0]),
            math.normFromFloat(u16, 1 - info.uv_bottom_right[1]),
        },
    });
}

pub fn drawText(renderer: *@This(), text_utf8: []const u8, mat: math.Mat3) !void {
    const baked = try renderer.font_face_loaded.bakeUtf8(renderer.alloc, text_utf8);
    defer renderer.alloc.free(baked);
    defer for (baked) |*arr| arr.deinit(renderer.alloc);

    for (baked, 0..) |*per_atlas, atlas| {
        for (per_atlas.items) |c| {
            const f_size: math.Vec2 = @floatFromInt(@as(@Vector(2, u16), c.size));
            const f_tl: math.Vec2 = @floatFromInt(@as(@Vector(2, i16), c.tl));

            try renderer.drawImage(.{
                .view = renderer.font_face_loaded.atlases.items[atlas].view,
                .mat = math.matMulMany(math.Mat3, .{
                    mat,
                    math.Mat3{
                        .{ f_size[0], 0, f_tl[0] },
                        .{ 0, -f_size[1], f_tl[1] },
                        .{ 0, 0, 1 },
                    },
                }),
                .uv_top_left = c.uv_tl,
                .uv_bottom_right = c.uv_br,
            });
        }
    }
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
    // 2 unorm16x2 first is top left, last is bottom right
    uv_bounds: [4]u16,
    id: u32,
};

const PerFrame = struct {
    image_resource_set: gpu.ResourceSet,
};
