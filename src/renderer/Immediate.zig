const std = @import("std");
const gpu = @import("../gpu/gpu.zig");
const math = @import("../math.zig");
const text = @import("../text.zig");
const Immediate = @This();

alloc: std.mem.Allocator,
stream_alloc: gpu.PushAllocator,
staging: gpu.Buffer,
stage_mapping: []u8,
box_renderer: ?BoxRenderer,
image_renderer: ?ImageRenderer,
text_renderer: ?TextRenderer,
frame_data: ?FrameData,

pub const InitInfo = struct {
    alloc: std.mem.Allocator,
    device: gpu.Device,
    frames_in_flight: u32,
    streaming_buffer_size_pf: gpu.Size,
    color_format: gpu.Image.Format,
    box_info: ?BoxRenderer.InitInfo = null,
    image_info: ?ImageRenderer.InitInfo = null,
    text_info: ?TextRenderer.InitInfo = null,
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
        .image_renderer = null,
        .text_renderer = null,
        .frame_data = null,
    };

    if (info.box_info) |_|
        try BoxRenderer.init(&immediate, info);
    errdefer if (info.box_info) |_|
        BoxRenderer.deinit(&immediate, info.device);

    if (info.image_info) |_|
        try ImageRenderer.init(&immediate, info);
    errdefer if (info.image_info) |_|
        ImageRenderer.deinit(&immediate, info.device);

    if (info.text_info) |_|
        try TextRenderer.init(&immediate, info);
    errdefer if (info.text_info) |_|
        TextRenderer.deinit(&immediate, info.device);

    return immediate;
}

pub fn deinit(immediate: *Immediate, device: gpu.Device) void {
    if (immediate.text_renderer) |_|
        TextRenderer.deinit(immediate, device);

    if (immediate.image_renderer) |_|
        ImageRenderer.deinit(immediate, device);

    if (immediate.box_renderer) |_|
        BoxRenderer.deinit(immediate, device);

    immediate.stream_alloc.buffer.deinit(device, immediate.alloc);
    immediate.staging.deinit(device, immediate.alloc);
}

pub fn begin(immediate: *Immediate, image_size: [2]u16) !void {
    if (immediate.box_renderer) |*x| {
        x.vertex_data.clearRetainingCapacity();
    }

    if (immediate.image_renderer) |*x| {
        x.draws.clearRetainingCapacity();
        x.resource_sets.nextFrame();
    }

    if (immediate.text_renderer) |*x| {
        x.resource_sets.nextFrame();

        for (x.per_atlas.items) |*y| {
            y.vertex_input.clearRetainingCapacity();
            y.buffer_offset = 0;
        }
    }

    immediate.stream_alloc.nextFrame();
    immediate.frame_data = .{
        .image_size = image_size,
    };
}

pub fn render(immediate: *Immediate, device: gpu.Device, cmd_encoder: gpu.CommandEncoder, image_view: gpu.Image.View) !void {
    if (immediate.box_renderer) |_| try BoxRenderer.upload(immediate);
    if (immediate.text_renderer) |_| try TextRenderer.upload(immediate);

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

    if (immediate.box_renderer) |_| try BoxRenderer.render(immediate, render_pass);
    if (immediate.image_renderer) |_| try ImageRenderer.render(immediate, device, render_pass);
    if (immediate.text_renderer) |_| try TextRenderer.render(immediate, device, render_pass);

    render_pass.cmdEnd();
}

const black: [4]u8 = .{ 0, 0, 0, 255 };
pub const DrawRectInfo = struct {
    transform: Transform,
    color: [4]u8 = black,
};

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
        .pivot = math.normFromFloatVec(@Vector(2, i16), s_pivot),
        .color = info.color,
    });
}

pub const DrawLineInfo = struct {
    start: NormWithOffset2D,
    end: NormWithOffset2D,
    thickness: u16 = 1,
    color: [4]u8 = black,
};

pub fn drawLine(immediate: *Immediate, info: DrawLineInfo) !void {
    const i16x2 = @Vector(2, i16);
    const start: i16x2 = info.start.pixels(immediate.frame_data.?.image_size);
    const end: i16x2 = info.end.pixels(immediate.frame_data.?.image_size);
    const to = end - start;

    const to_f: math.Vec2 = @floatFromInt(to);
    const length = math.length(to_f);
    if (length == 0) return;

    const to_unit = to_f / math.splat2(f32, length);

    try immediate.box_renderer.?.vertex_data.append(immediate.alloc, .{
        .pos = start,
        .size = .{ @intFromFloat(length), @intCast(info.thickness) },
        .cos = math.normFromFloat(i16, to_unit[0]),
        .sin = math.normFromFloat(i16, to_unit[1]),
        // center left
        .pivot = .{
            math.normFromFloat(i16, -1),
            0,
        },
        .color = info.color,
    });
}

pub const DrawImageInfo = struct {
    view: gpu.Image.View,
    transform: Transform,
};

pub fn drawImage(immediate: *Immediate, info: DrawImageInfo) !void {
    try immediate.image_renderer.?.draws.append(immediate.alloc, info);
}

pub const DrawTextInfo = struct {
    font_face: *text.Face,
    height_px: u16,
    height_in_atlas_px: u16,
    pos: NormWithOffset2D,
    text: []const u8,
    color: [4]u8,
    outline_width: f32 = 0,
    outline_color: [4]u8 = @splat(0),
};

pub fn drawText(immediate: *Immediate, info: DrawTextInfo) !void {
    const this = &immediate.text_renderer.?;

    const u16x2 = @Vector(2, u16);
    const i16x2 = @Vector(2, i16);
    const u32x2 = @Vector(2, u32);
    const i32x2 = @Vector(2, i32);
    const image_size: u16x2 = immediate.frame_data.?.image_size;
    const start: i32x2 = @as(i16x2, info.pos.pixels(image_size));
    const size_ratio = @as(f32, @floatFromInt(info.height_px)) / @as(f32, @floatFromInt(info.height_in_atlas_px));

    const not_def = info.font_face.notDefGlyphIndex();
    var iter: std.unicode.Utf8Iterator = .{
        .bytes = info.text,
        .i = 0,
    };

    // preload all glyphs used
    while (iter.nextCodepoint()) |codepoint| {
        const index = info.font_face.glyphIndexFromUnicode(codepoint) orelse not_def;
        try this.cache.loadGlyph(.{
            .face = info.font_face,
            .height = info.height_in_atlas_px,
            .index = index,
        });
    }
    const initial_atlas_count = this.per_atlas.items.len;
    try this.per_atlas.resize(immediate.alloc, this.cache.current_atlas_id + 1);
    @memset(this.per_atlas.items[initial_atlas_count..], .{});

    var positioner: text.GlyphPositioner = try .init(.{
        .cache = this.cache,
        .face = info.font_face,
        .height_px = info.height_in_atlas_px,
    });

    iter.i = 0;
    while (iter.nextCodepoint()) |codepoint| {
        const positioned = try positioner.position(codepoint);

        const tl_rel = @as(i16x2, positioned.pos_tl) * @as(i32x2, @splat(info.height_px)) / @as(i32x2, @splat(info.height_in_atlas_px));
        const tl = tl_rel + start;

        const size_u: u32x2 = @as(u16x2, positioned.size) * @as(u32x2, @splat(info.height_px)) / @as(u32x2, @splat(info.height_in_atlas_px));
        if (size_u[0] == 0 or size_u[1] == 0) continue;
        const size: i32x2 = @intCast(size_u);
        const br = tl + @as(i32x2, .{ size[0], -size[1] });

        const per_atlas = &this.per_atlas.items[positioned.atlas_id];
        try per_atlas.vertex_input.append(immediate.alloc, .{
            .tl = @as(i16x2, @intCast(tl)),
            .br = @as(i16x2, @intCast(br)),
            .uv_tl = positioned.uv_tl,
            .uv_br = positioned.uv_br,
            .color = info.color,
            .outline_color = info.outline_color,
            .outline_width = @intFromFloat((info.outline_width / size_ratio) * (1 << 3)),
        });
    }
}

pub const NormWithOffset = struct {
    norm: f32 = 0,
    /// offset in pixels
    offset: i16 = 0,

    pub fn pixels(this: NormWithOffset, length: u16) i16 {
        const length_f: f32 = @floatFromInt(length);
        if (!std.math.isFinite(this.norm)) return this.offset;

        const scaled: f32 = this.norm * length_f;
        const clamped = math.clampToIntBounds(i16, scaled);

        const clamped_i: i32 = @intFromFloat(clamped);
        const result = clamped_i + this.offset;

        return @intCast(math.clampToIntBounds(i16, result));
    }
};

pub const NormWithOffset2D = struct {
    /// bottom left = (0, 0), top right = (1, 1)
    norm: [2]f32 = @splat(0),
    /// offset in pixels
    offset: [2]i16 = @splat(0),

    const u16x2 = @Vector(2, u16);
    const i16x2 = @Vector(2, i16);
    pub fn pixels(this: NormWithOffset2D, image_size: [2]u16) [2]i16 {
        const f_image_size: math.Vec2 = @floatFromInt(@as(u16x2, image_size));
        const from_norm = @as(math.Vec2, this.norm) * f_image_size;
        const i_from_norm: i16x2 = @intFromFloat(from_norm);
        return @as(i16x2, i_from_norm + this.offset);
    }
};

pub const Transform = struct {
    pos: NormWithOffset2D,
    size: NormWithOffset2D,
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
                .dst_alpha_factor = .one_minus_src_alpha,
                .alpha_op = .add,
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

    fn render(immediate: *Immediate, render_pass: gpu.RenderPassEncoder) !void {
        const this = &immediate.box_renderer.?;
        const count = this.vertex_data.items.len;
        if (count == 0) return;

        const pc: PushConstants = .{
            .image_size = @as(math.Vec2, @floatFromInt(@as(@Vector(2, u16), immediate.frame_data.?.image_size))),
        };

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

    const PushConstants = extern struct {
        image_size: [2]f32,
    };
};

const ImageRenderer = struct {
    pipeline: gpu.GraphicsPipeline,
    resource_layout: gpu.ResourceSet.Layout,
    resource_sets: gpu.FrameRingPool(gpu.ResourceSet, gpu.ResourceSet.init, struct { gpu.Device, gpu.ResourceSet.Layout, std.mem.Allocator }),
    sampler: gpu.Sampler,
    draws: std.ArrayList(DrawImageInfo),

    const InitInfo = struct {
        shaders: []const gpu.Shader,
    };

    fn init(immediate: *Immediate, info: Immediate.InitInfo) !void {
        const layout = try info.device.initResourceLayout(.{
            .alloc = info.alloc,
            .descriptors = &.{.{
                .t = .image,
                .stages = .{ .pixel = true },
                .flags = .{},
                .binding = 0,
                .count = 1,
            }},
        });
        errdefer layout.deinit(info.device, info.alloc);

        const pipeline = try info.device.initGraphicsPipeline(.{
            .alloc = info.alloc,
            .render_target_desc = .{
                .color_format = info.color_format,
                .depth_format = null,
            },
            .shaders = info.image_info.?.shaders,
            .push_constant_ranges = &.{.{
                .size = @sizeOf(PushConstants),
                .offset = 0,
                .stages = .{ .vertex = true },
            }},
            .resource_layouts = &.{layout},
            .blend_info = .{
                .src_color_factor = .src_alpha,
                .dst_color_factor = .one_minus_src_alpha,
                .color_op = .add,
                .src_alpha_factor = .one,
                .dst_alpha_factor = .one_minus_src_alpha,
                .alpha_op = .add,
            },
        });
        errdefer pipeline.deinit(info.device, info.alloc);

        const sampler = try info.device.initSampler(.{
            .alloc = info.alloc,
            .min_filter = .linear,
            .mag_filter = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
        });
        errdefer sampler.deinit(info.device, info.alloc);

        immediate.image_renderer = .{
            .pipeline = pipeline,
            .resource_layout = layout,
            .resource_sets = try .init(info.alloc, info.frames_in_flight),
            .sampler = sampler,
            .draws = .empty,
        };
    }

    fn deinit(immediate: *Immediate, device: gpu.Device) void {
        const this = &immediate.image_renderer.?;

        for (this.resource_sets.free_list.items) |x| x.deinit(device, immediate.alloc);
        for (this.resource_sets.in_use_lists) |list|
            for (list.items) |x| x.deinit(device, immediate.alloc);
        this.resource_sets.deinit(immediate.alloc);
        this.pipeline.deinit(device, immediate.alloc);
        this.resource_layout.deinit(device, immediate.alloc);
        this.sampler.deinit(device, immediate.alloc);
        this.draws.deinit(immediate.alloc);
    }

    fn render(immediate: *Immediate, device: gpu.Device, render_pass: gpu.RenderPassEncoder) !void {
        const this = &immediate.image_renderer.?;
        if (this.draws.items.len == 0) return;

        try this.resource_sets.ensureFree(immediate.alloc, .{ device, this.resource_layout, immediate.alloc }, this.draws.items.len);
        render_pass.cmdBindPipeline(this.pipeline);

        for (this.draws.items) |draw| {
            const image_size: @Vector(2, u16) = immediate.frame_data.?.image_size;
            const image_size_f: math.Vec2 = @floatFromInt(image_size);

            const resource_set = this.resource_sets.allocateAssumeCapacity();
            try resource_set.update(device, &.{.{
                .binding = 0,
                .data = .{ .image = &.{.{
                    .view = draw.view,
                    .sampler = this.sampler,
                    .layout = .shader_read_only,
                }} },
            }}, immediate.alloc);

            const i16x2 = @Vector(2, i16);
            const pos: i16x2 = draw.transform.pos.pixels(image_size);
            const size: i16x2 = draw.transform.size.pixels(image_size);

            const pos_f: math.Vec2 = @floatFromInt(pos);
            const size_f: math.Vec2 = @floatFromInt(size);

            const pc: PushConstants = .{
                .image_size = image_size_f,
                .pos = pos_f,
                .size = size_f,
                .cos = @cos(draw.transform.angle),
                .sin = @sin(draw.transform.angle),
                .pivot = draw.transform.pivot,
            };

            render_pass.cmdPushConstants(this.pipeline, .{
                .offset = 0,
                .size = @sizeOf(PushConstants),
                .stages = .{ .vertex = true },
            }, std.mem.asBytes(&pc));
            render_pass.cmdBindResourceSets(this.pipeline, &.{resource_set}, 0);

            render_pass.cmdDraw(.{
                .vertex_count = 6,
                .indexed = false,
            });
        }
    }

    const PushConstants = extern struct {
        image_size: [2]f32,
        pos: [2]f32,
        size: [2]f32,
        cos: f32,
        sin: f32,
        pivot: [2]f32,
    };
};

pub const TextRenderer = struct {
    cache: *text.GlyphCache,
    pipeline: gpu.GraphicsPipeline,
    resource_layout: gpu.ResourceSet.Layout,
    resource_sets: gpu.FrameRingPool(gpu.ResourceSet, gpu.ResourceSet.init, struct { gpu.Device, gpu.ResourceSet.Layout, std.mem.Allocator }),
    sampler: gpu.Sampler,
    per_atlas: std.ArrayList(PerAtlas),

    const InitInfo = struct {
        glyph_cache: *text.GlyphCache,
        shaders: []const gpu.Shader,
    };

    fn init(immediate: *Immediate, info: Immediate.InitInfo) !void {
        const this_info = &info.text_info.?;

        const layout = try info.device.initResourceLayout(.{
            .alloc = info.alloc,
            .descriptors = &.{.{
                .t = .image,
                .stages = .{ .pixel = true },
                .flags = .{},
                .binding = 0,
                .count = 1,
            }},
        });
        errdefer layout.deinit(info.device, info.alloc);

        const pipeline = try info.device.initGraphicsPipeline(.{
            .alloc = info.alloc,
            .render_target_desc = .{
                .color_format = info.color_format,
                .depth_format = null,
            },
            .shaders = this_info.shaders,
            .push_constant_ranges = &.{.{
                .size = @sizeOf(PushConstants),
                .offset = 0,
                .stages = .{ .vertex = true },
            }},
            .vertex_input_bindings = &.{.{
                .binding = 0,
                .rate = .per_instance,
                .fields = &.{
                    // bounds
                    .{ .type = .sint16x4 },
                    // uv bounds
                    .{ .type = .unorm16x4 },
                    // color
                    .{ .type = .unorm8x4 },
                    // outline color
                    .{ .type = .unorm8x4 },
                    // outline width
                    .{ .type = .uint8 },
                },
            }},
            .resource_layouts = &.{layout},
            .blend_info = .{
                .src_color_factor = .one,
                .dst_color_factor = .one_minus_src_alpha,
                .color_op = .add,
                .src_alpha_factor = .one,
                .dst_alpha_factor = .one_minus_src_alpha,
                .alpha_op = .add,
            },
        });
        errdefer pipeline.deinit(info.device, info.alloc);

        const sampler = try info.device.initSampler(.{
            .alloc = info.alloc,
            .min_filter = .linear,
            .mag_filter = .linear,
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
        });
        errdefer sampler.deinit(info.device, info.alloc);

        immediate.text_renderer = .{
            .cache = this_info.glyph_cache,
            .pipeline = pipeline,
            .resource_layout = layout,
            .resource_sets = try .init(info.alloc, info.frames_in_flight),
            .sampler = sampler,
            .per_atlas = .empty,
        };
    }

    fn deinit(immediate: *Immediate, device: gpu.Device) void {
        const this = &immediate.text_renderer.?;

        for (this.resource_sets.free_list.items) |x| x.deinit(device, immediate.alloc);
        for (this.resource_sets.in_use_lists) |list|
            for (list.items) |x| x.deinit(device, immediate.alloc);
        this.resource_sets.deinit(immediate.alloc);
        this.pipeline.deinit(device, immediate.alloc);
        this.resource_layout.deinit(device, immediate.alloc);
        this.sampler.deinit(device, immediate.alloc);

        for (this.per_atlas.items) |*x| x.vertex_input.deinit(immediate.alloc);
        this.per_atlas.deinit(immediate.alloc);
    }

    fn upload(immediate: *Immediate) !void {
        const this = &immediate.text_renderer.?;

        for (this.per_atlas.items) |*per_atlas| {
            const data = per_atlas.vertex_input.items;
            if (data.len == 0) continue;

            const region = try immediate.stream_alloc.allocTAligned(VertexInput, data.len, .@"4");
            const staging = immediate.stage_mapping[region.offset..][0..region.size];
            @memcpy(staging, std.mem.sliceAsBytes(data));
            per_atlas.buffer_offset = region.offset;
        }
    }

    fn render(immediate: *Immediate, device: gpu.Device, render_pass: gpu.RenderPassEncoder) !void {
        const this = &immediate.text_renderer.?;

        try this.resource_sets.ensureFree(immediate.alloc, .{ device, this.resource_layout, immediate.alloc }, this.per_atlas.items.len);
        render_pass.cmdBindPipeline(this.pipeline);

        const image_size: @Vector(2, u16) = immediate.frame_data.?.image_size;
        const image_size_f: math.Vec2 = @floatFromInt(image_size);
        const pc: PushConstants = .{ .image_size = image_size_f };
        render_pass.cmdPushConstants(this.pipeline, .{
            .offset = 0,
            .size = @sizeOf(PushConstants),
            .stages = .{ .vertex = true },
        }, std.mem.asBytes(&pc));

        for (this.per_atlas.items, 0..) |*per_atlas, atlas_id| {
            const count = per_atlas.vertex_input.items.len;
            if (count == 0) continue;

            const resource_set = this.resource_sets.allocateAssumeCapacity();
            try resource_set.update(device, &.{.{
                .binding = 0,
                .data = .{ .image = &.{.{
                    .view = this.cache.atlases.items[atlas_id].view,
                    .sampler = this.sampler,
                    .layout = .shader_read_only,
                }} },
            }}, immediate.alloc);

            render_pass.cmdBindResourceSets(this.pipeline, &.{resource_set}, 0);
            render_pass.cmdBindVertexBuffer(0, .{
                .buffer = immediate.stream_alloc.buffer,
                .offset = per_atlas.buffer_offset,
                .size = count * @sizeOf(VertexInput),
            });

            render_pass.cmdDraw(.{
                .vertex_count = 6,
                .instance_count = @intCast(count),
                .indexed = false,
            });
        }
    }

    const PerAtlas = struct {
        vertex_input: std.ArrayList(VertexInput) = .empty,
        buffer_offset: gpu.Size = 0,
    };

    const VertexInput = extern struct {
        tl: [2]i16,
        br: [2]i16,
        /// unorm
        uv_tl: [2]u16,
        /// unorm
        uv_br: [2]u16,
        color: [4]u8,
        outline_color: [4]u8,
        /// 5.3 fractional pixels
        outline_width: u8,
    };

    const PushConstants = extern struct {
        image_size: [2]f32,
    };
};
