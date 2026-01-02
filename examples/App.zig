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

render_pass_desc: gpu.RenderPass.Desc,
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

    this.window = try mw.Window.init(alloc, "diamond example", .{ 100, 100 }, &this.event_queue);
    errdefer this.window.deinit();

    this.instance = try gpu.Instance.init(true, alloc);
    errdefer this.instance.deinit(alloc);

    const physical_device = try this.instance.bestPhysicalDevice(alloc);
    this.device = try this.instance.initDevice(&physical_device, alloc);
    errdefer this.device.deinit(alloc);

    this.display = try this.device.initDisplay(&this.window, alloc);
    errdefer this.display.deinit(alloc);

    this.render_pass_desc = try this.device.initRenderPassDesc(this.display.image_format);
    errdefer this.render_pass_desc.deinit(&this.device);

    this.vertex_buffer = try this.device.initBuffer(@sizeOf(@TypeOf(vertex_data)), .{
        .vertex = true,
        .map_write = true,
    });
    errdefer this.vertex_buffer.deinit(&this.device);

    this.index_buffer = try this.device.initBuffer(@sizeOf(@TypeOf(indices)), .{
        .index = true,
        .map_write = true,
    });
    errdefer this.index_buffer.deinit(&this.device);

    {
        const vertex_data_bytes = std.mem.sliceAsBytes(&vertex_data);
        const vertex_mapping = try this.vertex_buffer.map(&this.device);
        const index_bytes = std.mem.sliceAsBytes(&indices);
        const index_mapping = try this.index_buffer.map(&this.device);

        var tmp_cmd_buffer = try gpu.CommandBuffer.init(&this.device);
        var fence = try gpu.Fence.init(&this.device, false);
        @memcpy(vertex_mapping[0..vertex_data_bytes.len], vertex_data_bytes);
        @memcpy(index_mapping[0..index_bytes.len], index_bytes);
        this.vertex_buffer.unmap(&this.device);
        this.index_buffer.unmap(&this.device);

        try tmp_cmd_buffer.begin(&this.device);
        tmp_cmd_buffer.queueFlushBuffer(&this.device, &this.vertex_buffer);
        tmp_cmd_buffer.queueFlushBuffer(&this.device, &this.index_buffer);
        try tmp_cmd_buffer.end(&this.device);
        try tmp_cmd_buffer.submit(&this.device, &.{}, &.{}, fence);
        try fence.wait(&this.device, std.time.ns_per_s);
        tmp_cmd_buffer.deinit(&this.device);
        fence.deinit(&this.device);
    }

    this.vertex_shader = try createShader(&this.device, "res/shaders/triangle.vert.spv", .vertex, alloc);
    errdefer this.vertex_shader.deinit(&this.device);

    this.pixel_shader = try createShader(&this.device, "res/shaders/triangle.frag.spv", .pixel, alloc);
    errdefer this.pixel_shader.deinit(&this.device);

    this.shader_set = try gpu.Shader.Set.init(this.vertex_shader, this.pixel_shader, &.{
        .float32x2,
        .float32x3,
    }, alloc);
    errdefer this.shader_set.deinit(alloc);

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
    errdefer this.resource_layout.deinit(&this.device, alloc);

    this.graphics_pipeline = try gpu.GraphicsPipeline.init(.{
        .alloc = alloc,
        .device = &this.device,
        .render_pass_desc = this.render_pass_desc,
        .shader_set = this.shader_set,
        .resource_layouts = &.{this.resource_layout},
        .framebuffer_size = this.display.image_size,
    });
    errdefer this.graphics_pipeline.deinit(&this.device);

    this.frame_in_flight = 0;
    this.frames_in_flight_data = try alloc.alloc(PerFrameInFlight, this.display.images.len);
    errdefer alloc.free(this.frames_in_flight_data);

    for (this.frames_in_flight_data, 0..) |*x, i| {
        errdefer for (this.frames_in_flight_data[0 .. i - 1]) |*x2| x2.deinit(this);
        x.* = try .init(this, i, alloc);
    }

    this.cam_pos = .{ 0, 0, 1 };
    this.cam_fov = math.rad(70.0);
}

pub fn deinit(this: *@This(), alloc: std.mem.Allocator) void {
    this.device.waitUntilIdle() catch @panic("failed to wait for device");

    for (this.frames_in_flight_data) |*x| x.deinit(this);
    alloc.free(this.frames_in_flight_data);

    this.graphics_pipeline.deinit(&this.device);
    this.resource_layout.deinit(&this.device, alloc);
    this.shader_set.deinit(alloc);
    this.pixel_shader.deinit(&this.device);
    this.vertex_shader.deinit(&this.device);
    this.index_buffer.deinit(&this.device);
    this.vertex_buffer.deinit(&this.device);
    this.render_pass_desc.deinit(&this.device);

    this.display.deinit(alloc);
    this.device.deinit(alloc);
    this.instance.deinit(alloc);
    this.window.deinit();
    this.event_queue.deinit();
}

pub fn loop(this: *@This(), alloc: std.mem.Allocator) !bool {
    var rebuild: bool = false;
    const per_frame = &this.frames_in_flight_data[this.frame_in_flight];
    try per_frame.presented_fence.wait(&this.device, std.time.ns_per_s);
    try per_frame.presented_fence.reset(&this.device);

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
    const framebuffer = &this.frames_in_flight_data[image_index].framebuffer;
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
        if (this.window.isKeyDown(.minus))
            this.cam_fov -= fov_speed * dt;
        if (this.window.isKeyDown(.equal))
            this.cam_fov += fov_speed * dt;

        if (!math.eql(move_vector, @as(math.Vec3, @splat(0)))) {
            move_vector = math.normalize(move_vector);
            move_vector *= @splat(dt * 0.75);
            this.cam_pos += move_vector;
        }
    }

    const mvp = math.matMulMany(.{
        math.perspective(aspect_ratio, this.cam_fov, 0.1, 3),
        math.translate(-this.cam_pos),
        math.scale(@splat(0.75)),
        math.rotateX(time_s * 0.5),
    });

    {
        const mapping = try per_frame.uniform_buffer.map(&this.device);
        defer per_frame.uniform_buffer.unmap(&this.device);

        @memcpy(mapping, std.mem.sliceAsBytes(&math.toArray(mvp)));
    }

    try per_frame.write_command_buffer.reset(&this.device);
    try per_frame.write_command_buffer.begin(&this.device);
    per_frame.write_command_buffer.queueFlushBuffer(&this.device, &per_frame.uniform_buffer);
    try per_frame.write_command_buffer.end(&this.device);
    try per_frame.write_command_buffer.submit(&this.device, &.{}, &.{per_frame.uniform_written_semaphore}, null);

    try per_frame.command_buffer.reset(&this.device);
    try per_frame.command_buffer.begin(&this.device);
    per_frame.command_buffer.queueBeginRenderPass(&this.device, this.render_pass_desc, framebuffer.*, this.display.image_size);

    per_frame.command_buffer.queueBindPipeline(&this.device, this.graphics_pipeline, this.display.image_size);
    per_frame.command_buffer.queueBindVertexBuffer(&this.device, this.vertex_buffer.getRegion());
    per_frame.command_buffer.queueBindIndexBuffer(&this.device, this.index_buffer.getRegion(), .uint8);
    try per_frame.command_buffer.queueBindResourceSets(&this.device, &this.graphics_pipeline, &.{per_frame.resource_set}, 0, alloc);
    per_frame.command_buffer.queueDraw(.{
        .device = &this.device,
        .vertex_count = 6,
        .indexed = true,
    });

    per_frame.command_buffer.queueEndRenderPass(&this.device);
    try per_frame.command_buffer.end(&this.device);
    try per_frame.command_buffer.submit(&this.device, &.{ per_frame.image_available_semaphore, per_frame.uniform_written_semaphore }, &.{per_frame.render_finished_semaphore}, null);

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

    if (rebuild) try this.rebuildDisplay(alloc);

    return !this.window.shouldClose();
}

fn rebuildDisplay(this: *@This(), alloc: std.mem.Allocator) !void {
    try this.device.waitUntilIdle();
    for (this.frames_in_flight_data) |*per_frame| {
        per_frame.framebuffer.deinit(&this.device);
    }

    try this.display.rebuild(this.window.getFramebufferSize(), alloc);

    for (this.frames_in_flight_data, 0..) |*per_frame, i| {
        per_frame.framebuffer = try .init(&this.device, this.render_pass_desc, this.display.image_size, &.{this.display.image_views[i]});
    }
}

const PerFrameInFlight = struct {
    framebuffer: gpu.Framebuffer,
    command_buffer: gpu.CommandBuffer,
    write_command_buffer: gpu.CommandBuffer,
    uniform_written_semaphore: gpu.Semaphore,
    image_available_semaphore: gpu.Semaphore,
    render_finished_semaphore: gpu.Semaphore,
    presented_fence: gpu.Fence,

    uniform_buffer: gpu.Buffer,
    resource_set: gpu.ResourceSet,

    pub fn init(app: *App, i: usize, alloc: std.mem.Allocator) !@This() {
        var this: @This() = undefined;

        this.framebuffer = try app.device.initFramebuffer(app.render_pass_desc, app.display.image_size, &.{app.display.image_views[i]});
        errdefer this.framebuffer.deinit(&app.device);

        this.command_buffer = try app.device.initCommandBuffer();
        errdefer this.command_buffer.deinit(&app.device);

        this.write_command_buffer = try app.device.initCommandBuffer();
        errdefer this.write_command_buffer.deinit(&app.device);

        this.uniform_written_semaphore = try app.device.initSemaphore();
        errdefer this.uniform_written_semaphore.deinit(&app.device);

        this.image_available_semaphore = try app.device.initSemaphore();
        errdefer this.image_available_semaphore.deinit(&app.device);

        this.render_finished_semaphore = try app.device.initSemaphore();
        errdefer this.render_finished_semaphore.deinit(&app.device);

        this.presented_fence = try app.device.initFence(true);
        errdefer this.presented_fence.deinit(&app.device);

        this.uniform_buffer = try app.device.initBuffer(@sizeOf(mw.math.Mat4), .{
            .uniform = true,
            .map_write = true,
        });
        errdefer this.uniform_buffer.deinit(&app.device);

        this.resource_set = try .init(&app.device, &app.resource_layout);
        errdefer this.resource_set.deinit(&app.device);
        try this.resource_set.update(&app.device, &.{
            .{
                .binding = 0,
                .data = .{
                    .uniform = &.{
                        this.uniform_buffer.getRegion(),
                    },
                },
            },
        }, alloc);

        return this;
    }

    pub fn deinit(this: *@This(), app: *App) void {
        this.framebuffer.deinit(&app.device);
        this.command_buffer.deinit(&app.device);
        this.image_available_semaphore.deinit(&app.device);
        this.render_finished_semaphore.deinit(&app.device);
        this.uniform_written_semaphore.deinit(&app.device);
        this.presented_fence.deinit(&app.device);

        this.uniform_buffer.deinit(&app.device);
        this.resource_set.deinit(&app.device);
    }
};

fn createShader(device: *gpu.Device, filepath: []const u8, stage: gpu.Shader.Stage, alloc: std.mem.Allocator) !gpu.Shader {
    const file = try std.fs.cwd().openFile(filepath, .{ .mode = .read_only });
    defer file.close();

    const fileSize = try file.getEndPos();
    const buffer = try alloc.alloc(u32, try std.math.divCeil(usize, fileSize, @sizeOf(u32)));
    defer alloc.free(buffer);

    const read = try file.readAll(std.mem.sliceAsBytes(buffer));
    if (read != fileSize)
        return error.CouldntReadShaderFile;
    return gpu.Shader.fromSpirv(device, stage, buffer);
}

const PerVertex = extern struct {
    pos: [2]f32,
    color: [3]f32,
};

const vertex_data: [4]PerVertex = .{
    .{
        .pos = .{ -0.5, -0.5 },
        .color = .{ 1, 0, 0 },
    },
    .{
        .pos = .{ 0.5, -0.5 },
        .color = .{ 0, 1, 0 },
    },
    .{
        .pos = .{ -0.5, 0.5 },
        .color = .{ 0, 0, 1 },
    },
    .{
        .pos = .{ 0.5, 0.5 },
        .color = .{ 0, 0, 0 },
    },
};

const indices: [6]u8 = .{ 0, 1, 2, 1, 2, 3 };
