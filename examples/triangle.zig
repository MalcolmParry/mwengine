const std = @import("std");
const mw = @import("mwengine");
pub const tracy_impl = @import("tracy_impl");
pub const tracy = @import("tracy");
const gpu = mw.gpu;

var window: mw.Window = undefined;

fn eventHandler() !void {
    while (window.eventPending()) {
        const event = window.popEvent() orelse break;

        switch (event.type) {
            .closed => {},
        }
    }
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

pub fn main() !void {
    var tracy_allocator: tracy.Allocator = .{ .parent = std.heap.smp_allocator };
    const alloc = tracy_allocator.allocator();

    window = try mw.Window.init("TEST", .{ 480, 340 }, alloc);
    try window.setTitle("TEST", alloc);
    defer window.deinit();

    var instance = try gpu.Instance.init(true, alloc);
    defer instance.deinit(alloc);

    const physical_device = try instance.bestPhysicalDevice(alloc);
    var device = try instance.initDevice(&physical_device, alloc);
    defer device.deinit(alloc);

    var display = try device.initDisplay(&window, alloc);
    const frames_in_flight = display.image_views.len;
    defer display.deinit(alloc);

    var render_pass = try display.initRenderPass();
    defer render_pass.deinit(&display);

    const framebuffers = try alloc.alloc(gpu.Framebuffer, display.image_views.len);
    defer alloc.free(framebuffers);
    for (framebuffers, display.image_views) |*framebuffer, image_view| {
        framebuffer.* = try .init(&device, render_pass, display.image_size, &.{image_view});
    }
    defer for (framebuffers) |*framebuffer| {
        framebuffer.deinit(&device);
    };

    var vertex_shader = try createShader(&device, "res/shaders/triangle.vert.spv", .vertex, alloc);
    defer vertex_shader.deinit(&device);

    var pixel_shader = try createShader(&device, "res/shaders/triangle.frag.spv", .pixel, alloc);
    defer pixel_shader.deinit(&device);

    var shader_set = try gpu.Shader.Set.init(vertex_shader, pixel_shader, &.{
        .float32x2,
        .float32x3,
    }, alloc);
    defer shader_set.deinit(alloc);

    var vertex_buffer = try device.initBuffer(@sizeOf(@TypeOf(vertex_data)), .{
        .vertex = true,
        .map_write = true,
    });
    defer vertex_buffer.deinit(&device);

    var index_buffer = try device.initBuffer(@sizeOf(@TypeOf(indices)), .{
        .index = true,
        .map_write = true,
    });
    defer index_buffer.deinit(&device);

    const uniform: [16]f32 = mw.math.toArray(mw.math.rotateZ(mw.math.pi / 4.0));
    var uniform_buffer = try device.initBuffer(@sizeOf(@TypeOf(uniform)), .{
        .uniform = true,
        .map_write = true,
    });
    defer uniform_buffer.deinit(&device);

    {
        const vertex_data_bytes = std.mem.sliceAsBytes(&vertex_data);
        const vertex_mapping = try vertex_buffer.map(&device);
        const index_bytes = std.mem.sliceAsBytes(&indices);
        const index_mapping = try index_buffer.map(&device);
        const uniform_bytes = std.mem.sliceAsBytes(&uniform);
        const uniform_mapping = try uniform_buffer.map(&device);

        var tmp_cmd_buffer = try gpu.CommandBuffer.init(&device);
        var fence = try gpu.Fence.init(&device, false);
        @memcpy(vertex_mapping[0..vertex_data_bytes.len], vertex_data_bytes);
        @memcpy(index_mapping[0..index_bytes.len], index_bytes);
        @memcpy(uniform_mapping[0..uniform_bytes.len], uniform_bytes);
        vertex_buffer.unmap(&device);
        index_buffer.unmap(&device);

        try tmp_cmd_buffer.begin(&device);
        tmp_cmd_buffer.queueFlushBuffer(&device, &vertex_buffer);
        tmp_cmd_buffer.queueFlushBuffer(&device, &index_buffer);
        tmp_cmd_buffer.queueFlushBuffer(&device, &uniform_buffer);
        try tmp_cmd_buffer.end(&device);
        try tmp_cmd_buffer.submit(&device, &.{}, &.{}, fence);
        try fence.wait(&device, .all, std.time.ns_per_s);
        tmp_cmd_buffer.deinit(&device);
        fence.deinit(&device);
    }

    var resource_layout = try device.initResouceLayout(.{
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
    defer resource_layout.deinit(&device, alloc);

    var resource_set = try device.initResouceSet(&resource_layout);
    defer resource_set.deinit(&device);
    try resource_set.update(&device, &.{
        .{
            .binding = 0,
            .data = .{
                .uniform = &.{
                    uniform_buffer.getRegion(),
                },
            },
        },
    }, alloc);

    var graphics_pipeline = try gpu.GraphicsPipeline.init(.{
        .alloc = alloc,
        .device = &device,
        .render_pass = render_pass,
        .shader_set = shader_set,
        .resource_layouts = &.{resource_layout},
        .framebuffer_size = display.image_size,
    });
    defer graphics_pipeline.deinit(&device);

    const command_buffers = try alloc.alloc(gpu.CommandBuffer, frames_in_flight);
    for (command_buffers) |*command_buffer| {
        command_buffer.* = try .init(&device);
    }
    defer {
        for (command_buffers) |*command_buffer| {
            command_buffer.deinit(&device);
        }
        alloc.free(command_buffers);
    }

    const image_available_semaphores = try alloc.alloc(gpu.Semaphore, frames_in_flight);
    for (image_available_semaphores) |*x| {
        x.* = try .init(&device);
    }
    defer {
        for (image_available_semaphores) |*x| {
            x.deinit(&device);
        }
        alloc.free(image_available_semaphores);
    }

    const render_finished_semaphores = try alloc.alloc(gpu.Semaphore, frames_in_flight);
    for (render_finished_semaphores) |*x| {
        x.* = try .init(&device);
    }
    defer {
        for (render_finished_semaphores) |*x| {
            x.deinit(&device);
        }
        alloc.free(render_finished_semaphores);
    }

    const in_flight_fences = try alloc.alloc(gpu.Fence, frames_in_flight);
    for (in_flight_fences) |*x| {
        x.* = try .init(&device, true);
    }
    defer {
        for (in_flight_fences) |*x| {
            x.deinit(&device);
        }
        alloc.free(in_flight_fences);
    }

    defer device.waitUntilIdle() catch @panic("failed waiting for device");
    var frame: usize = 0;
    while (!window.shouldClose()) {
        var should_rebuild: bool = false;
        var command_buffer = command_buffers[frame];
        const image_available_semaphore = image_available_semaphores[frame];
        const render_finished_semaphore = render_finished_semaphores[frame];
        var in_flight_fence = in_flight_fences[frame];

        try in_flight_fence.wait(&device, .all, std.time.ns_per_s);
        try in_flight_fence.reset(&device);

        const framebuffer_index = blk: {
            for (0..3) |_| {
                switch (try display.acquireImageIndex(image_available_semaphore, null, std.time.ns_per_s)) {
                    .success => |index| break :blk index,
                    .suboptimal => |index| {
                        should_rebuild = true;
                        break :blk index;
                    },
                    .out_of_date => try rebuildDisplay(&device, &display, render_pass, framebuffers, alloc),
                }
            }

            return error.Failed;
        };

        const framebuffer = framebuffers[framebuffer_index];

        try command_buffer.reset(&device);
        try command_buffer.begin(&device);
        command_buffer.queueBeginRenderPass(&device, render_pass, framebuffer, display.image_size);
        command_buffer.queueBindPipeline(&device, graphics_pipeline, display.image_size);
        try command_buffer.queueBindResourceSets(&device, &graphics_pipeline, &.{resource_set}, 0, alloc);
        command_buffer.queueBindVertexBuffer(&device, vertex_buffer.getRegion());
        command_buffer.queueBindIndexBuffer(&device, index_buffer.getRegion(), .uint8);
        command_buffer.queueDraw(.{
            .device = &device,
            .vertex_count = 6,
            .indexed = true,
        });
        command_buffer.queueEndRenderPass(&device);
        try command_buffer.end(&device);
        try command_buffer.submit(&device, &.{image_available_semaphore}, &.{render_finished_semaphore}, null);
        if (try display.presentImage(framebuffer_index, &.{render_finished_semaphore}, in_flight_fence) != .success) should_rebuild = true;

        if (should_rebuild)
            try rebuildDisplay(&device, &display, render_pass, framebuffers, alloc);

        window.update();
        try eventHandler();

        frame = (frame + 1) % frames_in_flight;
    }
}

fn rebuildDisplay(device: *gpu.Device, display: *gpu.Display, render_pass: gpu.RenderPass, framebuffers: []gpu.Framebuffer, alloc: std.mem.Allocator) !void {
    try device.waitUntilIdle();
    for (framebuffers) |*x| {
        x.deinit(device);
    }
    try display.rebuild(window.getFramebufferSize(), alloc);
    for (framebuffers, display.image_views) |*x, image_view| {
        x.* = try .init(device, render_pass, display.image_size, &.{image_view});
    }
}

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
