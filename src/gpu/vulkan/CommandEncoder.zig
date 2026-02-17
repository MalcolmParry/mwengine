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

pub fn cmdCopyBuffer(this: gpu.CommandEncoder, device: gpu.Device, src: gpu.Buffer.Region, dst: gpu.Buffer.Region) void {
    std.debug.assert(src.size(device) == dst.size(device));
    const copy_region: vk.BufferCopy = .{
        .size = src.size(device),
        .src_offset = src.offset,
        .dst_offset = dst.offset,
    };

    device.vk.device.cmdCopyBuffer(this.vk.command_buffer, src.buffer.vk.buffer, dst.buffer.vk.buffer, 1, @ptrCast(&copy_region));
}

pub fn cmdCopyBufferToImage(this: gpu.CommandEncoder, info: gpu.CommandEncoder.BufferToImageCopyInfo) void {
    const signed_offset: @Vector(3, i32) = @intCast(info.image_offset);

    const buffer_image_copy: vk.BufferImageCopy = .{
        .buffer_offset = info.src.offset,
        .buffer_row_length = info.row_stride orelse 0,
        .buffer_image_height = 0,
        .image_offset = .{
            .x = signed_offset[0],
            .y = signed_offset[1],
            .z = signed_offset[2],
        },
        .image_extent = .{
            .width = info.image_size[0],
            .height = info.image_size[1],
            .depth = info.image_size[2],
        },
        .image_subresource = .{
            .aspect_mask = Image.aspectToNative(info.aspect),
            .mip_level = 0,
            .base_array_layer = info.layer_offset,
            .layer_count = info.layer_count,
        },
    };

    info.device.vk.device.cmdCopyBufferToImage(
        this.vk.command_buffer,
        info.src.buffer.vk.buffer,
        info.dst.vk.image,
        Image.layoutToNative(info.layout),
        1,
        @ptrCast(&buffer_image_copy),
    );
}

pub fn stageToNative(stage: gpu.GraphicsPipeline.Stages) vk.PipelineStageFlags {
    return .{
        .top_of_pipe_bit = stage.pipeline_start,
        .bottom_of_pipe_bit = stage.pipeline_end,
        .color_attachment_output_bit = stage.color_attachment_output,
        .early_fragment_tests_bit = stage.early_depth_tests,
        .transfer_bit = stage.transfer,
        .vertex_input_bit = stage.vertex_input,
        .vertex_shader_bit = stage.vertex_shader,
        .fragment_shader_bit = stage.pixel_shader,
    };
}

pub fn stageToNative2(stage: gpu.GraphicsPipeline.Stages) vk.PipelineStageFlags2KHR {
    return .{
        .top_of_pipe_bit = stage.pipeline_start,
        .bottom_of_pipe_bit = stage.pipeline_end,
        .color_attachment_output_bit = stage.color_attachment_output,
        .early_fragment_tests_bit = stage.early_depth_tests,
        .all_transfer_bit = stage.transfer,
        .vertex_input_bit = stage.vertex_input,
        .vertex_shader_bit = stage.vertex_shader,
        .fragment_shader_bit = stage.pixel_shader,
    };
}

pub fn accessToNative(access: gpu.Access) vk.AccessFlags2KHR {
    return .{
        .color_attachment_write_bit = access.color_attachment_write,
        .depth_stencil_attachment_read_bit = access.depth_stencil_read,
        .depth_stencil_attachment_write_bit = access.depth_stencil_write,
        .transfer_write_bit = access.transfer_write,
        .vertex_attribute_read_bit = access.vertex_read,
        .uniform_read_bit = access.uniform_read,
        .shader_read_bit = access.shader_read,
    };
}

pub fn cmdMemoryBarrier(this: gpu.CommandEncoder, device: gpu.Device, memory_barriers: []const gpu.CommandEncoder.MemoryBarrier, alloc: std.mem.Allocator) !void {
    var image_count: usize = 0;
    var buffer_count: usize = 0;

    for (memory_barriers) |barrier| {
        switch (barrier) {
            .image => |_| image_count += 1,
            .buffer => |_| buffer_count += 1,
        }
    }

    var image_barriers: std.ArrayList(vk.ImageMemoryBarrier2KHR) = try .initCapacity(alloc, image_count);
    defer image_barriers.deinit(alloc);

    var buffer_barriers: std.ArrayList(vk.BufferMemoryBarrier2KHR) = try .initCapacity(alloc, buffer_count);
    defer buffer_barriers.deinit(alloc);

    for (memory_barriers) |barrier| {
        switch (barrier) {
            .image => |image| image_barriers.appendAssumeCapacity(.{
                .image = image.image.vk.image,
                .old_layout = Image.layoutToNative(image.old_layout),
                .new_layout = Image.layoutToNative(image.new_layout),
                .src_stage_mask = stageToNative2(image.src_stage),
                .dst_stage_mask = stageToNative2(image.dst_stage),
                .src_access_mask = accessToNative(image.src_access),
                .dst_access_mask = accessToNative(image.dst_access),
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .subresource_range = .{
                    .aspect_mask = Image.aspectToNative(image.aspect),
                    .base_mip_level = 0,
                    .level_count = vk.REMAINING_MIP_LEVELS,
                    .base_array_layer = image.layer_offset,
                    .layer_count = if (image.layer_count) |x| x else vk.REMAINING_ARRAY_LAYERS,
                },
            }),
            .buffer => |buffer| buffer_barriers.appendAssumeCapacity(.{
                .buffer = buffer.region.buffer.vk.buffer,
                .size = switch (buffer.region.size_or_whole) {
                    .size => |x| x,
                    .whole => vk.WHOLE_SIZE,
                },
                .offset = buffer.region.offset,
                .src_stage_mask = stageToNative2(buffer.src_stage),
                .dst_stage_mask = stageToNative2(buffer.dst_stage),
                .src_access_mask = accessToNative(buffer.src_access),
                .dst_access_mask = accessToNative(buffer.dst_access),
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
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

    pub fn cmdBindVertexBuffer(this: gpu.RenderPassEncoder, device: gpu.Device, binding: u32, buffer_region: gpu.Buffer.Region) void {
        const offset = buffer_region.offset;
        device.vk.device.cmdBindVertexBuffers(this.vk.command_encoder.vk.command_buffer, binding, 1, @ptrCast(&buffer_region.buffer.vk.buffer), @ptrCast(&offset));
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
            info.device.vk.device.cmdDrawIndexed(this.vk.command_encoder.vk.command_buffer, info.vertex_count, info.instance_count, 0, @intCast(info.first_vertex), @intCast(info.first_instance));
        } else {
            info.device.vk.device.cmdDraw(this.vk.command_encoder.vk.command_buffer, info.vertex_count, info.instance_count, @intCast(info.first_vertex), @intCast(info.first_instance));
        }
    }
};
