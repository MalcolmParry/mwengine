const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const Semaphore = @import("wait_objects.zig").Semaphore;
const ResourceSet = @import("ResourceSet.zig");
const Image = @import("Image.zig");

const CommandEncoder = @This();
pub const Handle = CommandEncoder;

command_buffer: vk.CommandBuffer,

pub fn init(device: gpu.Device) !gpu.CommandEncoder {
    var command_buffer: vk.CommandBuffer = .null_handle;
    try device.vk.device.allocateCommandBuffers(&.{
        .command_pool = device.vk.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&command_buffer));

    return .{ .vk = .{ .command_buffer = command_buffer } };
}

pub fn deinit(this: gpu.CommandEncoder, device: gpu.Device) void {
    device.vk.device.freeCommandBuffers(device.vk.command_pool, 1, @ptrCast(&this.vk.command_buffer));
}

pub fn begin(this: gpu.CommandEncoder, device: gpu.Device) !void {
    try device.vk.device.resetCommandBuffer(this.vk.command_buffer, .{});
    try device.vk.device.beginCommandBuffer(this.vk.command_buffer, &.{
        .flags = .{},
    });
}

pub fn end(this: gpu.CommandEncoder, device: gpu.Device) !void {
    try device.vk.device.endCommandBuffer(this.vk.command_buffer);
}

pub fn submit(this: gpu.CommandEncoder, device: gpu.Device, wait_semaphores: []const gpu.Semaphore, signal_semaphores: []const gpu.Semaphore, signal_fence: ?gpu.Fence) !void {
    // really cursed temporary solution
    const wait_dst_stage_mask: [5]vk.PipelineStageFlags = @splat(.{
        .color_attachment_output_bit = true,
    });

    const submit_info: vk.SubmitInfo = .{
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast(&this.vk.command_buffer),
        .wait_semaphore_count = @intCast(wait_semaphores.len),
        .p_wait_semaphores = Semaphore.nativesFromSlice(wait_semaphores),
        .p_wait_dst_stage_mask = @ptrCast(&wait_dst_stage_mask),
        .signal_semaphore_count = @intCast(signal_semaphores.len),
        .p_signal_semaphores = Semaphore.nativesFromSlice(signal_semaphores),
    };

    try device.vk.device.queueSubmit(device.vk.queue, 1, @ptrCast(&submit_info), if (signal_fence) |fence| fence.vk.fence else .null_handle);
}

pub fn cmdCopyBuffer(this: gpu.CommandEncoder, device: gpu.Device, src: gpu.Buffer.Region, dst: gpu.Buffer.Region) void {
    std.debug.assert(src.size(device) == dst.size(device));
    const copy_region: vk.BufferCopy = .{
        .size = src.size(device),
        .src_offset = src.offset,
        .dst_offset = dst.offset,
    };

    device.vk.device.cmdCopyBuffer(this.vk.command_buffer, src.buffer.vk.buffer, dst.buffer.vk.buffer, 1, @ptrCast(&copy_region));
}

pub fn stageToNative(stage: gpu.CommandEncoder.Stage) vk.PipelineStageFlags2KHR {
    return .{
        .top_of_pipe_bit = stage.pipeline_start,
        .bottom_of_pipe_bit = stage.pipeline_end,
        .color_attachment_output_bit = stage.color_attachment_output,
        .all_transfer_bit = stage.transfer,
        .vertex_shader_bit = stage.vertex_shader,
    };
}

pub fn accessToNative(access: gpu.CommandEncoder.Access) vk.AccessFlags2KHR {
    return .{
        .color_attachment_write_bit = access.color_attachment_write,
        .transfer_write_bit = access.transfer_write,
        .uniform_read_bit = access.uniform_read,
    };
}

pub fn cmdMemoryBarrier(this: gpu.CommandEncoder, device: gpu.Device, memory_barriers: []const gpu.CommandEncoder.MemoryBarrier) void {
    const max = 8;

    var image_buffer: [max]vk.ImageMemoryBarrier2KHR = undefined;
    var image_barriers: std.ArrayList(vk.ImageMemoryBarrier2KHR) = .initBuffer(&image_buffer);

    var buffer_buffer: [max]vk.BufferMemoryBarrier2KHR = undefined;
    var buffer_barriers: std.ArrayList(vk.BufferMemoryBarrier2KHR) = .initBuffer(&buffer_buffer);

    for (memory_barriers) |barrier| {
        switch (barrier) {
            .image => |image| image_barriers.appendAssumeCapacity(.{
                .image = image.image.vk.image,
                .old_layout = Image.layoutToNative(image.old_layout),
                .new_layout = Image.layoutToNative(image.new_layout),
                .src_stage_mask = stageToNative(image.src_stage),
                .dst_stage_mask = stageToNative(image.dst_stage),
                .src_access_mask = accessToNative(image.src_access),
                .dst_access_mask = accessToNative(image.dst_access),
                .src_queue_family_index = device.vk.queue_family_index,
                .dst_queue_family_index = device.vk.queue_family_index,
                .subresource_range = .{
                    .aspect_mask = Image.aspectToNative(image.aspect),
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            }),
            .buffer => |buffer| buffer_barriers.appendAssumeCapacity(.{
                .buffer = buffer.region.buffer.vk.buffer,
                .size = switch (buffer.region.size_or_whole) {
                    .size => |x| x,
                    .whole => vk.WHOLE_SIZE,
                },
                .offset = buffer.region.offset,
                .src_stage_mask = stageToNative(buffer.src_stage),
                .dst_stage_mask = stageToNative(buffer.dst_stage),
                .src_access_mask = accessToNative(buffer.src_access),
                .dst_access_mask = accessToNative(buffer.dst_access),
                .src_queue_family_index = device.vk.queue_family_index,
                .dst_queue_family_index = device.vk.queue_family_index,
            }),
        }
    }

    device.vk.device.cmdPipelineBarrier2KHR(this.vk.command_buffer, &.{
        .image_memory_barrier_count = @intCast(image_barriers.items.len),
        .p_image_memory_barriers = image_barriers.items.ptr,
        .buffer_memory_barrier_count = @intCast(buffer_barriers.items.len),
        .p_buffer_memory_barriers = buffer_barriers.items.ptr,
    });
}

pub const cmdBeginRenderPass = RenderPassEncoder.cmdBegin;
pub const RenderPassEncoder = struct {
    pub const Handle = RenderPassEncoder;

    command_encoder: gpu.CommandEncoder,

    pub fn cmdBegin(command_encoder: gpu.CommandEncoder, info: gpu.RenderPassEncoder.BeginInfo) gpu.RenderPassEncoder {
        const color_attachment: vk.RenderingAttachmentInfo = .{
            .image_layout = .attachment_optimal,
            .image_view = info.target.color_image_view.vk.image_view,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{
                .color = .{
                    .float_32 = info.target.color_clear_value,
                },
            },
            .resolve_image_layout = .undefined,
            .resolve_image_view = .null_handle,
            .resolve_mode = .{},
        };

        const depth_attachment: vk.RenderingAttachmentInfo = .{
            .image_layout = .depth_stencil_attachment_optimal,
            .image_view = if (info.target.depth_image_view) |x| x.vk.image_view else .null_handle,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{
                .depth_stencil = .{
                    .depth = 1.0,
                    .stencil = 0.0,
                },
            },
            .resolve_image_layout = .undefined,
            .resolve_image_view = .null_handle,
            .resolve_mode = .{},
        };

        info.device.vk.device.cmdBeginRenderingKHR(command_encoder.vk.command_buffer, &.{
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
            .p_depth_attachment = if (info.target.depth_image_view) |_| @ptrCast(&depth_attachment) else null,
            .flags = .{},
        });

        return .{ .vk = .{ .command_encoder = command_encoder } };
    }

    pub fn cmdEnd(this: gpu.RenderPassEncoder, device: gpu.Device) void {
        device.vk.device.cmdEndRenderingKHR(this.vk.command_encoder.vk.command_buffer);
    }

    pub fn cmdBindPipeline(this: gpu.RenderPassEncoder, device: gpu.Device, graphics_pipeline: gpu.GraphicsPipeline, image_size: @Vector(2, u32)) void {
        device.vk.device.cmdBindPipeline(this.vk.command_encoder.vk.command_buffer, .graphics, graphics_pipeline.vk.pipeline);

        const viewport: vk.Viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(image_size[0]),
            .height = @floatFromInt(image_size[1]),
            .min_depth = 0,
            .max_depth = 1,
        };

        device.vk.device.cmdSetViewport(this.vk.command_encoder.vk.command_buffer, 0, 1, @ptrCast(&viewport));

        const scissor: vk.Rect2D = .{
            .extent = .{ .width = image_size[0], .height = image_size[1] },
            .offset = .{ .x = 0, .y = 0 },
        };

        device.vk.device.cmdSetScissor(this.vk.command_encoder.vk.command_buffer, 0, 1, @ptrCast(&scissor));
    }

    pub fn cmdBindVertexBuffer(this: gpu.RenderPassEncoder, device: gpu.Device, buffer_region: gpu.Buffer.Region) void {
        const first_binding = 0;
        const offset = buffer_region.offset;
        device.vk.device.cmdBindVertexBuffers(this.vk.command_encoder.vk.command_buffer, first_binding, 1, @ptrCast(&buffer_region.buffer.vk.buffer), @ptrCast(&offset));
    }

    pub fn cmdBindIndexBuffer(this: gpu.RenderPassEncoder, device: gpu.Device, buffer_region: gpu.Buffer.Region, index_type: gpu.RenderPassEncoder.IndexType) void {
        device.vk.device.cmdBindIndexBuffer(this.vk.command_encoder.vk.command_buffer, buffer_region.buffer.vk.buffer, buffer_region.offset, switch (index_type) {
            .uint16 => .uint16,
            .uint32 => .uint32,
        });
    }

    pub fn cmdBindResourceSets(this: gpu.RenderPassEncoder, device: gpu.Device, pipeline: gpu.GraphicsPipeline, resource_sets: []const gpu.ResourceSet, first: u32) void {
        var buffer: [64]u8 = undefined;
        var alloc = std.heap.FixedBufferAllocator.init(&buffer);
        const natives = ResourceSet.nativesFromSlice(resource_sets, alloc.allocator()) catch unreachable;

        device.vk.device.cmdBindDescriptorSets(
            this.vk.command_encoder.vk.command_buffer,
            .graphics,
            pipeline.vk.pipeline_layout,
            first,
            @intCast(resource_sets.len),
            natives.ptr,
            0,
            null,
        );
    }

    pub fn cmdPushConstants(this: gpu.RenderPassEncoder, device: gpu.Device, pipeline: gpu.GraphicsPipeline, range: gpu.PushConstantRange, data: [*]const u8) void {
        device.vk.device.cmdPushConstants(
            this.vk.command_encoder.vk.command_buffer,
            pipeline.vk.pipeline_layout,
            .{
                .vertex_bit = range.stages.vertex,
                .fragment_bit = range.stages.pixel,
            },
            range.offset,
            range.size,
            data,
        );
    }

    pub fn cmdDraw(this: gpu.RenderPassEncoder, info: gpu.RenderPassEncoder.DrawInfo) void {
        if (info.indexed) {
            info.device.vk.device.cmdDrawIndexed(this.vk.command_encoder.vk.command_buffer, info.vertex_count, 1, 0, 0, 0);
        } else {
            info.device.vk.device.cmdDraw(this.vk.command_encoder.vk.command_buffer, info.vertex_count, 1, 0, 0);
        }
    }
};
