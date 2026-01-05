const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const GraphicsPipeline = @import("GraphicsPipeline.zig");
const Semaphore = @import("wait_objects.zig").Semaphore;
const Fence = @import("wait_objects.zig").Fence;
const Buffer = @import("Buffer.zig");
const ResourceSet = @import("ResourceSet.zig");
const RenderTarget = @import("RenderTarget.zig");

_command_buffer: vk.CommandBuffer,

pub fn init(device: *Device) !@This() {
    var command_buffer: vk.CommandBuffer = .null_handle;
    try device._device.allocateCommandBuffers(&.{
        .command_pool = device._command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&command_buffer));

    return .{ ._command_buffer = command_buffer };
}

pub fn deinit(this: *@This(), device: *Device) void {
    device._device.freeCommandBuffers(device._command_pool, 1, @ptrCast(&this._command_buffer));
}

pub fn begin(this: *@This(), device: *Device) !void {
    try device._device.beginCommandBuffer(this._command_buffer, &.{
        .flags = .{},
    });
}

pub fn end(this: *@This(), device: *Device) !void {
    try device._device.endCommandBuffer(this._command_buffer);
}

pub fn reset(this: *@This(), device: *Device) !void {
    try device._device.resetCommandBuffer(this._command_buffer, .{});
}

pub fn submit(this: *@This(), device: *Device, wait_semaphores: []const Semaphore, signal_semaphores: []const Semaphore, signal_fence: ?Fence) !void {
    // really cursed temporary solution
    const wait_dst_stage_mask: [5]vk.PipelineStageFlags = @splat(.{
        .color_attachment_output_bit = true,
    });

    const submit_info: vk.SubmitInfo = .{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&this._command_buffer),
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = Semaphore._nativesFromSlice(wait_semaphores),
        .p_wait_dst_stage_mask = @ptrCast(&wait_dst_stage_mask),
        .signal_semaphore_count = @intCast(signal_semaphores.len),
        .p_signal_semaphores = Semaphore._nativesFromSlice(signal_semaphores),
    };

    try device._device.queueSubmit(device._queue, 1, @ptrCast(&submit_info), if (signal_fence) |fence| fence._fence else .null_handle);
}

pub fn cmdCopyBuffer(this: *@This(), device: *Device, src: Buffer.Region, dst: Buffer.Region) void {
    std.debug.assert(src.size == dst.size);
    const copy_region: vk.BufferCopy = .{
        .size = src.size,
        .src_offset = src.offset,
        .dst_offset = dst.offset,
    };

    device._device.cmdCopyBuffer(this._command_buffer, src.buffer._buffer, dst.buffer._buffer, 1, @ptrCast(&copy_region));
}

pub fn cmdFlushBuffer(this: *@This(), device: *Device, buffer: *Buffer) void {
    var staging: Buffer = .{
        ._staging = null,
        ._buffer = buffer._staging.?._buffer,
        ._memory_region = buffer._staging.?._memory_region,
        ._usage = .{},
        .size = buffer.size,
    };

    this.cmdCopyBuffer(device, .{
        .buffer = &staging,
        .offset = 0,
        .size = buffer.size,
    }, .{
        .buffer = buffer,
        .offset = 0,
        .size = buffer.size,
    });
}

// Graphics Commands
pub const RenderPassBeginInfo = struct {
    device: *Device,
    target: RenderTarget,
    image_size: @Vector(2, u32),
};

pub fn cmdBeginRenderPass(this: *@This(), info: RenderPassBeginInfo) void {
    const image_memory_barrier: vk.ImageMemoryBarrier2 = .{
        .src_access_mask = .{},
        .dst_access_mask = .{ .color_attachment_write_bit = true },
        .old_layout = .undefined,
        .new_layout = .color_attachment_optimal,
        .image = info.target.color_image._image,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .src_queue_family_index = 0,
        .dst_queue_family_index = 0,
        .src_stage_mask = .{ .top_of_pipe_bit = true },
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
    };

    info.device._device.cmdPipelineBarrier2KHR(this._command_buffer, &.{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = @ptrCast(&image_memory_barrier),
    });

    const color_attachment: vk.RenderingAttachmentInfo = .{
        .image_layout = .attachment_optimal,
        .image_view = info.target.color_image_view._image_view,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = .{
            .color = .{
                .float_32 = .{ 0, 0, 0, 0 },
            },
        },
        .resolve_image_layout = .undefined,
        .resolve_image_view = .null_handle,
        .resolve_mode = .{},
    };

    info.device._device.cmdBeginRenderingKHR(this._command_buffer, &.{
        .render_area = .{
            .offset = .{
                .x = 0,
                .y = 0,
            },
            .extent = .{
                .width = info.image_size[0],
                .height = info.image_size[1],
            },
        },
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment),
        .flags = .{},
    });
}

pub fn cmdEndRenderPass(this: *@This(), device: *Device) void {
    device._device.cmdEndRenderingKHR(this._command_buffer);
}

pub fn cmdBindPipeline(this: *@This(), device: *Device, graphics_pipeline: GraphicsPipeline, image_size: @Vector(2, u32)) void {
    device._device.cmdBindPipeline(this._command_buffer, .graphics, graphics_pipeline._pipeline);

    const viewport: vk.Viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(image_size[0]),
        .height = @floatFromInt(image_size[1]),
        .min_depth = 0,
        .max_depth = 1,
    };

    device._device.cmdSetViewport(this._command_buffer, 0, 1, @ptrCast(&viewport));

    const scissor: vk.Rect2D = .{
        .extent = .{ .width = image_size[0], .height = image_size[1] },
        .offset = .{ .x = 0, .y = 0 },
    };

    device._device.cmdSetScissor(this._command_buffer, 0, 1, @ptrCast(&scissor));
}

pub fn cmdBindVertexBuffer(this: *@This(), device: *Device, buffer_region: Buffer.Region) void {
    const first_binding = 0;
    const offset = buffer_region.offset;
    device._device.cmdBindVertexBuffers(this._command_buffer, first_binding, 1, @ptrCast(&buffer_region.buffer._buffer), @ptrCast(&offset));
}

const IndexType = enum {
    uint8,
    uint16,
    uint32,
};

pub fn cmdBindIndexBuffer(this: *@This(), device: *Device, buffer_region: Buffer.Region, index_type: IndexType) void {
    device._device.cmdBindIndexBuffer(this._command_buffer, buffer_region.buffer._buffer, buffer_region.offset, switch (index_type) {
        .uint8 => .uint8_khr,
        .uint16 => .uint16,
        .uint32 => .uint32,
    });
}

pub fn cmdBindResourceSets(this: *@This(), device: *Device, pipeline: *GraphicsPipeline, resource_sets: []const ResourceSet, first: u32) void {
    var buffer: [64]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(&buffer);
    const natives = ResourceSet._nativesFromSlice(resource_sets, alloc.allocator()) catch unreachable;

    device._device.cmdBindDescriptorSets(
        this._command_buffer,
        .graphics,
        pipeline._pipeline_layout,
        first,
        @intCast(resource_sets.len),
        natives.ptr,
        0,
        null,
    );
}

const DrawInfo = struct {
    device: *Device,
    vertex_count: u32,
    indexed: bool,
};

pub fn cmdDraw(this: *@This(), info: DrawInfo) void {
    if (info.indexed) {
        info.device._device.cmdDrawIndexed(this._command_buffer, info.vertex_count, 1, 0, 0, 0);
    } else {
        info.device._device.cmdDraw(this._command_buffer, info.vertex_count, 1, 0, 0);
    }
}
