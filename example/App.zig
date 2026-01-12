const std = @import("std");
const mw = @import("mwengine");
const gpu = mw.gpu;
const math = mw.math;
const App = @This();

timer: std.time.Timer,
frame_timer: std.time.Timer,
event_queue: mw.EventQueue,
window: mw.Window,
instance: gpu.Instance,
device: gpu.Device,
display: gpu.Display,
frame_in_flight: usize,

vertex_buffer: gpu.Buffer,
index_buffer: gpu.Buffer,
vertex_shader: gpu.Shader,
pixel_shader: gpu.Shader,
shader_set: gpu.Shader.Set,
resource_layout: gpu.ResourceSet.Layout,
graphics_pipeline: gpu.GraphicsPipeline,

frames_in_flight_data: []PerFrameInFlight,

cam_pos: math.Vec3,
cam_fov: f32,

pub fn init(this: *@This(), alloc: std.mem.Allocator) !void {
    this.timer = try .start();
    this.frame_timer = try .start();

    this.event_queue = try .init(alloc);
    errdefer this.event_queue.deinit();

    this.window = try mw.Window.init(alloc, "example", .{ 100, 100 }, &this.event_queue);
    errdefer this.window.deinit();

    this.instance = try gpu.Instance.init(true, alloc);
    errdefer this.instance.deinit(alloc);

    const physical_device = try this.instance.bestPhysicalDevice();
    this.device = try this.instance.initDevice(physical_device, alloc);
    errdefer this.device.deinit(alloc);

    this.display = try this.device.initDisplay(&this.window, alloc);
    errdefer this.display.deinit(alloc);

    this.vertex_buffer = try this.device.initBuffer(.{
        .size = @sizeOf(@TypeOf(vertex_data)),
        .loc = .device,
        .usage = .{
            .vertex = true,
            .dst = true,
        },
    });
    errdefer this.vertex_buffer.deinit(this.device);

    this.index_buffer = try this.device.initBuffer(.{
        .size = @sizeOf(@TypeOf(indices)),
        .loc = .device,
        .usage = .{
            .index = true,
            .dst = true,
        },
    });
    errdefer this.index_buffer.deinit(this.device);

    try this.device.setBufferRegions(&.{
        this.vertex_buffer.region(),
        this.index_buffer.region(),
    }, &.{
        std.mem.sliceAsBytes(&vertex_data),
        std.mem.sliceAsBytes(&indices),
    });

    this.vertex_shader = try createShader(this.device, "res/shaders/triangle.vert.spv", .vertex, alloc);
    errdefer this.vertex_shader.deinit(this.device, alloc);

    this.pixel_shader = try createShader(this.device, "res/shaders/triangle.frag.spv", .pixel, alloc);
    errdefer this.pixel_shader.deinit(this.device, alloc);

    this.shader_set = try gpu.Shader.Set.init(this.device, this.vertex_shader, this.pixel_shader, &.{
        .float32x2,
        .float32x3,
    }, alloc);
    errdefer this.shader_set.deinit(this.device, alloc);

    this.resource_layout = try this.device.initResouceLayout(.{
        .alloc = alloc,
        .descriptors = &.{
            .{
                .t = .uniform,
                .stage = .{ .vertex = true },
                .count = 1,
                .binding = 0,
            },
        },
    });
    errdefer this.resource_layout.deinit(this.device, alloc);

    this.graphics_pipeline = try this.device.initGraphicsPipeline(.{
        .alloc = alloc,
        .render_target_desc = .{
            .color_format = this.display.imageFormat(),
        },
        .shader_set = this.shader_set,
        .resource_layouts = &.{this.resource_layout},
    });
    errdefer this.graphics_pipeline.deinit(this.device);

    this.frame_in_flight = 0;
    this.frames_in_flight_data = try alloc.alloc(PerFrameInFlight, this.display.imageCount());
    errdefer alloc.free(this.frames_in_flight_data);

    for (this.frames_in_flight_data, 0..) |*x, i| {
        errdefer for (this.frames_in_flight_data[0 .. i - 1]) |*x2| x2.deinit(this);
        x.* = try .init(this, alloc);
    }

    this.cam_pos = .{ -1, 0, 0 };
    this.cam_fov = math.rad(70.0);
}

pub fn deinit(this: *@This(), alloc: std.mem.Allocator) void {
    this.device.waitUntilIdle();

    for (this.frames_in_flight_data) |*x| x.deinit(this);
    alloc.free(this.frames_in_flight_data);

    this.graphics_pipeline.deinit(this.device);
    this.resource_layout.deinit(this.device, alloc);
    this.shader_set.deinit(this.device, alloc);
    this.pixel_shader.deinit(this.device, alloc);
    this.vertex_shader.deinit(this.device, alloc);
    this.index_buffer.deinit(this.device);
    this.vertex_buffer.deinit(this.device);

    this.display.deinit(alloc);
    this.device.deinit(alloc);
    this.instance.deinit(alloc);
    this.window.deinit();
    this.event_queue.deinit();
}

pub fn loop(this: *@This(), alloc: std.mem.Allocator) !bool {
    var rebuild: bool = false;
    const per_frame = &this.frames_in_flight_data[this.frame_in_flight];
    try per_frame.presented_fence.wait(this.device, std.time.ns_per_s);
    try per_frame.presented_fence.reset(this.device);

    const image_index = blk: {
        for (0..3) |_| {
            switch (try this.display.acquireImageIndex(per_frame.image_available_semaphore, null, std.time.ns_per_s)) {
                .success => |i| break :blk i,
                .suboptimal => |i| {
                    rebuild = true;
                    break :blk i;
                },
                .out_of_date => return error.OutOfDate,
            }
        }

        return error.Failed;
    };
    const viewport = this.window.getFramebufferSize();
    const time_s = @as(f32, @floatFromInt(this.timer.read())) / std.time.ns_per_s;
    const aspect_ratio = @as(f32, @floatFromInt(viewport[0])) / @as(f32, @floatFromInt(viewport[1]));
    const dt_ns = this.frame_timer.lap();
    const dt = @as(f32, @floatFromInt(dt_ns)) / std.time.ns_per_s;

    {
        var move_vector: math.Vec3 = @splat(0);

        if (this.window.isKeyDown(.w))
            move_vector += math.dir_forward;
        if (this.window.isKeyDown(.s))
            move_vector -= math.dir_forward;
        if (this.window.isKeyDown(.a))
            move_vector -= math.dir_right;
        if (this.window.isKeyDown(.d))
            move_vector += math.dir_right;
        if (this.window.isKeyDown(.e))
            move_vector += math.dir_up;
        if (this.window.isKeyDown(.q))
            move_vector -= math.dir_up;

        const fov_speed = math.rad(50.0);
        const fov_max = math.rad(100.0);
        const fov_min = math.rad(40.0);
        if (this.window.isKeyDown(.minus))
            this.cam_fov -= fov_speed * dt;
        if (this.window.isKeyDown(.equal))
            this.cam_fov += fov_speed * dt;

        this.cam_fov = @min(fov_max, @max(fov_min, this.cam_fov));

        if (!math.eql(move_vector, @as(math.Vec3, @splat(0)))) {
            move_vector = math.normalize(move_vector);
            move_vector *= @splat(dt * 0.75);
            this.cam_pos += move_vector;
        }
    }

    const mvp = math.matMulMany(.{
        math.perspective(aspect_ratio, this.cam_fov, 0.1, 50),
        math.translate(-this.cam_pos),
        math.scale(@splat(0.75)),
        math.rotateY(time_s * 0.5),
    });

    per_frame.uniform_mapping.* = .{
        .mvp = math.toArray(mvp),
    };

    try per_frame.cmd_encoder.begin(this.device);
    per_frame.cmd_encoder.cmdCopyBuffer(
        this.device,
        per_frame.uniform_staging.region(),
        per_frame.uniform_buffer.region(),
    );

    per_frame.cmd_encoder.cmdMemoryBarrier(this.device, &.{
        .{ .image = .{
            .image = &this.display.image(image_index),
            .old_layout = .undefined,
            .new_layout = .color_attachment,
            .src_stage = .{ .pipeline_start = true },
            .dst_stage = .{ .color_attachment_output = true },
            .src_access = .{},
            .dst_access = .{ .color_attachment_write = true },
        } },
        .{ .buffer = .{
            .region = per_frame.uniform_buffer.region(),
            .src_stage = .{ .transfer = true },
            .dst_stage = .{ .vertex_shader = true },
            .src_access = .{ .transfer_write = true },
            .dst_access = .{ .uniform_read = true },
        } },
    });

    var render_pass = per_frame.cmd_encoder.cmdBeginRenderPass(.{
        .device = this.device,
        .image_size = this.display.imageSize(),
        .target = .{
            .color_clear_value = @splat(0),
            .color_image_view = this.display.imageView(image_index),
        },
    });

    render_pass.cmdBindPipeline(this.device, this.graphics_pipeline, this.display.imageSize());
    render_pass.cmdBindVertexBuffer(this.device, this.vertex_buffer.region());
    render_pass.cmdBindIndexBuffer(this.device, this.index_buffer.region(), .uint16);
    render_pass.cmdBindResourceSets(this.device, &this.graphics_pipeline, &.{per_frame.resource_set}, 0);
    render_pass.cmdDraw(.{
        .device = this.device,
        .vertex_count = 6,
        .indexed = true,
    });
    render_pass.cmdEnd(this.device);

    per_frame.cmd_encoder.cmdMemoryBarrier(this.device, &.{
        .{ .image = .{
            .image = &this.display.image(image_index),
            .old_layout = .color_attachment,
            .new_layout = .present_src,
            .src_stage = .{ .color_attachment_output = true },
            .dst_stage = .{ .pipeline_end = true },
            .src_access = .{ .color_attachment_write = true },
            .dst_access = .{},
        } },
    });

    try per_frame.cmd_encoder.end(this.device);
    try per_frame.cmd_encoder.submit(this.device, &.{per_frame.image_available_semaphore}, &.{per_frame.render_finished_semaphore}, null);

    switch (try this.display.presentImage(image_index, &.{per_frame.render_finished_semaphore}, per_frame.presented_fence)) {
        .success => {},
        .suboptimal => {
            rebuild = true;
        },
        .out_of_date => {
            return error.OutOfDate;
        },
    }

    this.frame_in_flight = (this.frame_in_flight + 1) % this.frames_in_flight_data.len;
    this.window.update();
    while (this.event_queue.pending()) {
        const event = this.event_queue.pop();

        switch (event) {
            .close => return false,
            .resize => rebuild = true,
            .key_down => |kc| {
                if (kc == .escape) return false;
            },
            else => {},
        }
    }

    if (rebuild) {
        this.device.waitUntilIdle();
        try this.display.rebuild(this.window.getFramebufferSize(), alloc);
    }

    return !this.window.shouldClose();
}

const PerFrameInFlight = struct {
    cmd_encoder: gpu.CommandEncoder,
    image_available_semaphore: gpu.Semaphore,
    render_finished_semaphore: gpu.Semaphore,
    presented_fence: gpu.Fence,

    uniform_buffer: gpu.Buffer,
    uniform_staging: gpu.Buffer,
    uniform_mapping: *UniformData,
    resource_set: gpu.ResourceSet,

    pub fn init(app: *App, alloc: std.mem.Allocator) !@This() {
        var this: @This() = undefined;

        this.cmd_encoder = try app.device.initCommandEncoder();
        errdefer this.cmd_encoder.deinit(app.device);

        this.image_available_semaphore = try app.device.initSemaphore();
        errdefer this.image_available_semaphore.deinit(app.device);

        this.render_finished_semaphore = try app.device.initSemaphore();
        errdefer this.render_finished_semaphore.deinit(app.device);

        this.presented_fence = try app.device.initFence(true);
        errdefer this.presented_fence.deinit(app.device);

        this.uniform_buffer = try app.device.initBuffer(.{
            .loc = .device,
            .usage = .{
                .uniform = true,
                .dst = true,
            },
            .size = @sizeOf(UniformData),
        });
        errdefer this.uniform_buffer.deinit(app.device);

        this.uniform_staging = try app.device.initBuffer(.{
            .loc = .host,
            .usage = .{ .src = true },
            .size = this.uniform_buffer.size,
        });
        errdefer this.uniform_staging.unmap(app.device);

        this.uniform_mapping = @ptrCast(@alignCast(try this.uniform_staging.map(app.device)));
        errdefer this.uniform_staging.unmap(app.device);

        this.resource_set = try .init(app.device, &app.resource_layout);
        errdefer this.resource_set.deinit(app.device);
        try this.resource_set.update(app.device, &.{
            .{
                .binding = 0,
                .data = .{
                    .uniform = &.{
                        this.uniform_buffer.region(),
                    },
                },
            },
        }, alloc);

        return this;
    }

    pub fn deinit(this: *@This(), app: *App) void {
        this.cmd_encoder.deinit(app.device);
        this.image_available_semaphore.deinit(app.device);
        this.render_finished_semaphore.deinit(app.device);
        this.presented_fence.deinit(app.device);

        this.uniform_staging.unmap(app.device);
        this.uniform_staging.deinit(app.device);
        this.uniform_buffer.deinit(app.device);
        this.resource_set.deinit(app.device);
    }
};

fn createShader(device: gpu.Device, filepath: []const u8, stage: gpu.Shader.Stage, alloc: std.mem.Allocator) !gpu.Shader {
    const file = try std.fs.cwd().openFile(filepath, .{ .mode = .read_only });
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer = try alloc.alloc(u32, try std.math.divCeil(usize, fileSize, @sizeOf(u32)));
    defer alloc.free(buffer);

    const read = try file.readAll(std.mem.sliceAsBytes(buffer));
    if (read != fileSize)
        return error.CouldntReadShaderFile;
    return gpu.Shader.fromSpirv(device, stage, buffer, alloc);
}

const PerVertex = extern struct {
    pos: [2]f32,
    color: [3]f32,
};

const UniformData = extern struct {
    mvp: [16]f32,
};

const vertex_data: [4]PerVertex = .{
    .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 0, 0 } },
};

const indices: [6]u16 = .{ 0, 1, 2, 1, 2, 3 };
