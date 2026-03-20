const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const Semaphore = @import("wait_objects.zig").Semaphore;
const ResourceSet = @import("ResourceSet.zig");
const Image = @import("Image.zig");
const Sampler = @import("Sampler.zig");

const CommandEncoder = @This();
pub const Handle = CommandEncoder;

command_buffer: vk.CommandBuffer,
dispatch: *const vk.DeviceWrapper,

pub fn init(device: gpu.Device) !gpu.CommandEncoder {
    var command_buffer: vk.CommandBuffer = .null_handle;
    try device.vk.device.allocateCommandBuffers(&.{
        .command_pool = device.vk.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&command_buffer));

    return .{ .vk = .{
        .command_buffer = command_buffer,
        .dispatch = device.vk.device.wrapper,
    } };
}

pub fn deinit(this: gpu.CommandEncoder, device: gpu.Device) void {
    device.vk.device.freeCommandBuffers(device.vk.command_pool, 1, @ptrCast(&this.vk.command_buffer));
}

pub fn begin(this: gpu.CommandEncoder) !void {
    try this.vk.dispatch.resetCommandBuffer(this.vk.command_buffer, .{});
    try this.vk.dispatch.beginCommandBuffer(this.vk.command_buffer, &.{
        .flags = .{},
    });
}

pub fn end(this: gpu.CommandEncoder) !void {
    try this.vk.dispatch.endCommandBuffer(this.vk.command_buffer);
}

pub fn cmdCopyBuffer(cmd_encoder: gpu.CommandEncoder, src: gpu.Buffer.Region, dst: gpu.Buffer.Region) void {
    std.debug.assert(src.size(cmd_encoder) == dst.size(cmd_encoder));

    const copy_region: vk.BufferCopy = .{
        .size = src.size(cmd_encoder),
        .src_offset = src.offset,
        .dst_offset = dst.offset,
    };

    cmd_encoder.vk.dispatch.cmdCopyBuffer(cmd_encoder.vk.command_buffer, src.buffer.vk.buffer, dst.buffer.vk.buffer, 1, @ptrCast(&copy_region));
}

pub fn cmdCopyBufferToImage(this: gpu.CommandEncoder, info: gpu.CommandEncoder.BufferToImageCopyInfo) void {
    const signed_offset: @Vector(3, i32) = @intCast(info.region.offset);

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
            .width = info.region.size[0],
            .height = info.region.size[1],
            .depth = info.region.size[2],
        },
        .image_subresource = .{
            .aspect_mask = Image.aspectToNative(info.subresource.aspect),
            .mip_level = info.subresource.mip_level,
            .base_array_layer = info.subresource.layer_offset,
            .layer_count = info.subresource.layer_count,
        },
    };

    this.vk.dispatch.cmdCopyBufferToImage(
        this.vk.command_buffer,
        info.src.buffer.vk.buffer,
        info.dst.vk.image,
        Image.layoutToNative(info.layout),
        1,
        @ptrCast(&buffer_image_copy),
    );
}

pub fn cmdCopyImageWithScaling(cmd_encoder: gpu.CommandEncoder, info: gpu.CommandEncoder.ImageCopyWithScalingInfo) void {
    const blit: vk.ImageBlit = .{
        .src_subresource = Image.subresourceLayersToNative(info.src_subresource),
        .dst_subresource = Image.subresourceLayersToNative(info.dst_subresource),
        .src_offsets = .{
            .{
                .x = @intCast(info.src_rect.offset[0]),
                .y = @intCast(info.src_rect.offset[1]),
                .z = 0,
            },
            .{
                .x = @intCast(info.src_rect.offset[0] + info.src_rect.size[0]),
                .y = @intCast(info.src_rect.offset[1] + info.src_rect.size[1]),
                .z = 1,
            },
        },
        .dst_offsets = .{
            .{
                .x = @intCast(info.dst_rect.offset[0]),
                .y = @intCast(info.dst_rect.offset[1]),
                .z = 0,
            },
            .{
                .x = @intCast(info.dst_rect.offset[0] + info.dst_rect.size[0]),
                .y = @intCast(info.dst_rect.offset[1] + info.dst_rect.size[1]),
                .z = 1,
            },
        },
    };

    cmd_encoder.vk.dispatch.cmdBlitImage(
        cmd_encoder.vk.command_buffer,
        info.src.vk.image,
        Image.layoutToNative(info.src_layout),
        info.dst.vk.image,
        Image.layoutToNative(info.dst_layout),
        1,
        @ptrCast(&blit),
        Sampler.filterToNative(info.filter),
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
        .transfer_read_bit = access.transfer_read,
        .transfer_write_bit = access.transfer_write,
        .vertex_attribute_read_bit = access.vertex_read,
        .uniform_read_bit = access.uniform_read,
        .shader_read_bit = access.shader_read,
    };
}

pub fn cmdMemoryBarrier(this: gpu.CommandEncoder, info: gpu.CommandEncoder.MemoryBarrierInfo) void {
    var remaining_image = info.image_barriers;
    var remaining_buffer = info.buffer_barriers;
    var image_buffer: [16]vk.ImageMemoryBarrier2 = undefined;
    var buffer_buffer: [16]vk.BufferMemoryBarrier2 = undefined;

    while (remaining_image.len > 0 or remaining_buffer.len > 0) {
        const image = if (remaining_image.len > image_buffer.len) remaining_image[0..image_buffer.len] else remaining_image;
        remaining_image = if (remaining_image.len > image_buffer.len) remaining_image[image_buffer.len..] else &.{};

        for (image, 0..) |barrier, i| {
            image_buffer[i] = .{
                .image = barrier.image.vk.image,
                .old_layout = Image.layoutToNative(barrier.old_layout),
                .new_layout = Image.layoutToNative(barrier.new_layout),
                .src_stage_mask = stageToNative2(barrier.src_stage),
                .dst_stage_mask = stageToNative2(barrier.dst_stage),
                .src_access_mask = accessToNative(barrier.src_access),
                .dst_access_mask = accessToNative(barrier.dst_access),
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .subresource_range = .{
                    .aspect_mask = Image.aspectToNative(barrier.subresource_range.aspect),
                    .base_mip_level = barrier.subresource_range.mip_offset,
                    .level_count = if (barrier.subresource_range.mip_count) |x| x else vk.REMAINING_MIP_LEVELS,
                    .base_array_layer = barrier.subresource_range.layer_offset,
                    .layer_count = if (barrier.subresource_range.layer_count) |x| x else vk.REMAINING_ARRAY_LAYERS,
                },
            };
        }

        const buffer = if (remaining_buffer.len > buffer_buffer.len) remaining_buffer[0..buffer_buffer.len] else remaining_buffer;
        remaining_buffer = if (remaining_buffer.len > buffer_buffer.len) remaining_buffer[buffer_buffer.len..] else &.{};

        for (buffer, 0..) |barrier, i| {
            buffer_buffer[i] = .{
                .buffer = barrier.region.buffer.vk.buffer,
                .size = switch (barrier.region.size_or_whole) {
                    .size => |x| x,
                    .whole => vk.WHOLE_SIZE,
                },
                .offset = barrier.region.offset,
                .src_stage_mask = stageToNative2(barrier.src_stage),
                .dst_stage_mask = stageToNative2(barrier.dst_stage),
                .src_access_mask = accessToNative(barrier.src_access),
                .dst_access_mask = accessToNative(barrier.dst_access),
                .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            };
        }

        this.vk.dispatch.cmdPipelineBarrier2KHR(this.vk.command_buffer, &.{
            .image_memory_barrier_count = @intCast(image.len),
            .p_image_memory_barriers = &image_buffer,
            .buffer_memory_barrier_count = @intCast(buffer.len),
            .p_buffer_memory_barriers = &buffer_buffer,
        });
    }
}

pub const cmdBeginRenderPass = RenderPassEncoder.cmdBegin;
pub const RenderPassEncoder = struct {
    pub const Handle = RenderPassEncoder;

    cmd_encoder: CommandEncoder,

    fn clearValueToVk(val: gpu.RenderAttachment.ClearValue) vk.ClearValue {
        return switch (val) {
            .color => |x| .{ .color = .{ .float_32 = x } },
            .depth => |x| .{ .depth_stencil = .{
                .depth = x,
                .stencil = 0,
            } },
        };
    }

    fn attachmentToNative(attachment: gpu.RenderAttachment, layout: vk.ImageLayout) vk.RenderingAttachmentInfo {
        return .{
            .image_layout = layout,
            .image_view = attachment.image_view.vk.image_view,
            .load_op = switch (attachment.load) {
                .dont_care => .dont_care,
                .load => .load,
                .clear => .clear,
            },
            .store_op = switch (attachment.store) {
                .dont_care => .dont_care,
                .store => .store,
            },
            .clear_value = switch (attachment.load) {
                .clear => |val| clearValueToVk(val),
                else => undefined,
            },
            .resolve_image_layout = .undefined,
            .resolve_image_view = .null_handle,
            .resolve_mode = .{},
        };
    }

    pub fn cmdBegin(command_encoder: gpu.CommandEncoder, info: gpu.RenderPassEncoder.BeginInfo) gpu.RenderPassEncoder {
        const color_attachment = attachmentToNative(info.target.color_attachment, .attachment_optimal);
        const depth_attachment: vk.RenderingAttachmentInfo = if (info.target.depth_attachment) |attachment|
            attachmentToNative(attachment, .depth_stencil_attachment_optimal)
        else
            undefined;

        command_encoder.vk.dispatch.cmdBeginRenderingKHR(command_encoder.vk.command_buffer, &.{
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
            .p_depth_attachment = if (info.target.depth_attachment) |_| @ptrCast(&depth_attachment) else null,
            .flags = .{},
        });

        return .{ .vk = .{ .cmd_encoder = command_encoder.vk } };
    }

    pub fn cmdEnd(this: gpu.RenderPassEncoder) void {
        this.vk.cmd_encoder.dispatch.cmdEndRenderingKHR(this.vk.cmd_encoder.command_buffer);
    }

    pub fn cmdBindPipeline(this: gpu.RenderPassEncoder, graphics_pipeline: gpu.GraphicsPipeline, image_size: @Vector(2, u32)) void {
        this.vk.cmd_encoder.dispatch.cmdBindPipeline(this.vk.cmd_encoder.command_buffer, .graphics, graphics_pipeline.vk.pipeline);

        const viewport: vk.Viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(image_size[0]),
            .height = @floatFromInt(image_size[1]),
            .min_depth = 0,
            .max_depth = 1,
        };

        this.vk.cmd_encoder.dispatch.cmdSetViewport(this.vk.cmd_encoder.command_buffer, 0, 1, @ptrCast(&viewport));

        const scissor: vk.Rect2D = .{
            .extent = .{ .width = image_size[0], .height = image_size[1] },
            .offset = .{ .x = 0, .y = 0 },
        };

        this.vk.cmd_encoder.dispatch.cmdSetScissor(this.vk.cmd_encoder.command_buffer, 0, 1, @ptrCast(&scissor));
    }

    pub fn cmdBindVertexBuffer(this: gpu.RenderPassEncoder, binding: u32, buffer_region: gpu.Buffer.Region) void {
        const offset = buffer_region.offset;
        this.vk.cmd_encoder.dispatch.cmdBindVertexBuffers(this.vk.cmd_encoder.command_buffer, binding, 1, @ptrCast(&buffer_region.buffer.vk.buffer), @ptrCast(&offset));
    }

    pub fn cmdBindIndexBuffer(this: gpu.RenderPassEncoder, buffer_region: gpu.Buffer.Region, index_type: gpu.RenderPassEncoder.IndexType) void {
        this.vk.cmd_encoder.dispatch.cmdBindIndexBuffer(this.vk.cmd_encoder.command_buffer, buffer_region.buffer.vk.buffer, buffer_region.offset, switch (index_type) {
            .uint16 => .uint16,
            .uint32 => .uint32,
        });
    }

    pub fn cmdBindResourceSets(this: gpu.RenderPassEncoder, pipeline: gpu.GraphicsPipeline, resource_sets: []const gpu.ResourceSet, first: u32) void {
        var buffer: [64]u8 = undefined;
        var alloc = std.heap.FixedBufferAllocator.init(&buffer);
        const natives = ResourceSet.nativesFromSlice(resource_sets, alloc.allocator()) catch unreachable;

        this.vk.cmd_encoder.dispatch.cmdBindDescriptorSets(
            this.vk.cmd_encoder.command_buffer,
            .graphics,
            pipeline.vk.pipeline_layout,
            first,
            @intCast(resource_sets.len),
            natives.ptr,
            0,
            null,
        );
    }

    pub fn cmdPushConstants(this: gpu.RenderPassEncoder, pipeline: gpu.GraphicsPipeline, range: gpu.PushConstantRange, data: [*]const u8) void {
        this.vk.cmd_encoder.dispatch.cmdPushConstants(
            this.vk.cmd_encoder.command_buffer,
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
            this.vk.cmd_encoder.dispatch.cmdDrawIndexed(this.vk.cmd_encoder.command_buffer, info.vertex_count, info.instance_count, 0, @intCast(info.first_vertex), @intCast(info.first_instance));
        } else {
            this.vk.cmd_encoder.dispatch.cmdDraw(this.vk.cmd_encoder.command_buffer, info.vertex_count, info.instance_count, @intCast(info.first_vertex), @intCast(info.first_instance));
        }
    }
};
