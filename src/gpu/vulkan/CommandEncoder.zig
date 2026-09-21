const std = @import("std");
const gpu = @import("../gpu.zig");
const vk = @import("vulkan");
const ResourceSet = @import("ResourceSet.zig");
const Image = @import("Image.zig");
const Sampler = @import("Sampler.zig");

const CommandEncoder = @This();
pub const Handle = *CommandEncoder;

command_buffer: vk.CommandBuffer,
dispatch: *const vk.DeviceWrapper,
arena: std.heap.ArenaAllocator.State,
gpa: std.mem.Allocator,
out_of_memory: bool = false,
debug: bool,

pub fn init(device: gpu.Device, alloc: std.mem.Allocator) gpu.CommandEncoder.InitError!gpu.CommandEncoder {
    const encoder = try alloc.create(CommandEncoder);
    errdefer alloc.destroy(encoder);

    var command_buffer: vk.CommandBuffer = .null_handle;
    device.vk.device.allocateCommandBuffers(&.{
        .command_pool = device.vk.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&command_buffer)) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };

    encoder.* = .{
        .command_buffer = command_buffer,
        .dispatch = device.vk.device.wrapper,
        .arena = .init,
        .gpa = alloc,
        .debug = device.vk.instance.maybe_debug_messenger != null,
    };

    return .{ .vk = encoder };
}

pub fn deinit(encoder: gpu.CommandEncoder, device: gpu.Device) void {
    const gpa = encoder.vk.gpa;
    device.vk.device.freeCommandBuffers(device.vk.command_pool, (&encoder.vk.command_buffer)[0..1]);
    encoder.vk.arena.promote(gpa).deinit();
    gpa.destroy(encoder.vk);
}

pub fn begin(encoder: gpu.CommandEncoder) gpu.CommandEncoder.BeginError!void {
    try encoder.vk.dispatch.resetCommandBuffer(encoder.vk.command_buffer, .{});
    encoder.vk.dispatch.beginCommandBuffer(encoder.vk.command_buffer, &.{
        .flags = .{},
    }) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.Unknown => error.Unknown,
    };
}

pub fn end(encoder: gpu.CommandEncoder) gpu.CommandEncoder.EndError!void {
    defer encoder.vk.out_of_memory = false;

    encoder.vk.dispatch.endCommandBuffer(encoder.vk.command_buffer) catch |err| return switch (err) {
        error.OutOfHostMemory => error.OutOfMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.InvalidVideoStdParametersKHR => unreachable,
        error.Unknown => error.Unknown,
    };

    if (encoder.vk.out_of_memory) return error.OutOfMemory;
}

pub fn cmdCopyBuffer(cmd_encoder: gpu.CommandEncoder, src: gpu.Buffer.Region, dst: gpu.Buffer.Region) void {
    std.debug.assert(src.size == dst.size);

    const copy_region: vk.BufferCopy = .{
        .size = src.size,
        .src_offset = src.offset,
        .dst_offset = dst.offset,
    };

    cmd_encoder.vk.dispatch.cmdCopyBuffer(cmd_encoder.vk.command_buffer, src.buffer.impl.vk.buffer, dst.buffer.impl.vk.buffer, (&copy_region)[0..1]);
}

pub fn cmdCopyBufferToImage(encoder: gpu.CommandEncoder, info: gpu.CommandEncoder.BufferToImageCopyInfo) void {
    const offset: gpu.Image.Size3DVec = info.region.offset;
    const signed_offset: @Vector(3, i32) = @intCast(offset);

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

    encoder.vk.dispatch.cmdCopyBufferToImage(
        encoder.vk.command_buffer,
        info.src.buffer.impl.vk.buffer,
        info.dst.impl.vk.image,
        Image.layoutToNative(info.layout),
        (&buffer_image_copy)[0..1],
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
        info.src.impl.vk.image,
        Image.layoutToNative(info.src_layout),
        info.dst.impl.vk.image,
        Image.layoutToNative(info.dst_layout),
        (&blit)[0..1],
        Sampler.filterToNative(info.filter),
    );
}

pub fn stageToNative(stage: gpu.PipelineStageFlags) vk.PipelineStageFlags2KHR {
    return .{
        .all_commands_bit = stage.all_commands,
        .top_of_pipe_bit = stage.pipeline_start,
        .bottom_of_pipe_bit = stage.pipeline_end,
        .color_attachment_output_bit = stage.color_attachment_output,
        .early_fragment_tests_bit = stage.early_depth_tests,
        .all_transfer_bit = stage.transfer,
        .vertex_input_bit = stage.vertex_input,
        .vertex_shader_bit = stage.vertex_shader,
        .fragment_shader_bit = stage.pixel_shader,
        .draw_indirect_bit = stage.draw_indirect,
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
        .indirect_command_read_bit = access.indirect_cmd_read,
    };
}

pub fn cmdMemoryBarrier(encoder: gpu.CommandEncoder, info: gpu.CommandEncoder.MemoryBarrierInfo) void {
    var arena_obj = encoder.vk.arena.promote(encoder.vk.gpa);
    defer {
        _ = arena_obj.reset(.retain_capacity);
        encoder.vk.arena = arena_obj.state;
    }
    const arena = arena_obj.allocator();

    const image_barriers = arena.alloc(vk.ImageMemoryBarrier2, info.image_barriers.len) catch {
        encoder.vk.out_of_memory = true;
        return;
    };

    const buffer_barriers = arena.alloc(vk.BufferMemoryBarrier2, info.buffer_barriers.len) catch {
        encoder.vk.out_of_memory = true;
        return;
    };

    for (info.image_barriers, image_barriers) |barrier, *native| {
        native.* = .{
            .image = barrier.image.impl.vk.image,
            .old_layout = Image.layoutToNative(barrier.old_layout),
            .new_layout = Image.layoutToNative(barrier.new_layout),
            .src_stage_mask = stageToNative(barrier.src_stage),
            .dst_stage_mask = stageToNative(barrier.dst_stage),
            .src_access_mask = accessToNative(barrier.src_access),
            .dst_access_mask = accessToNative(barrier.dst_access),
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .subresource_range = .{
                .aspect_mask = Image.aspectToNative(barrier.subresource_range.aspect),
                .base_mip_level = barrier.subresource_range.mip_offset,
                .level_count = switch (barrier.subresource_range.mip_count) {
                    .count => |x| x,
                    .all => vk.REMAINING_MIP_LEVELS,
                },
                .base_array_layer = barrier.subresource_range.layer_offset,
                .layer_count = switch (barrier.subresource_range.layer_count) {
                    .count => |x| x,
                    .all => vk.REMAINING_ARRAY_LAYERS,
                },
            },
        };
    }

    for (info.buffer_barriers, buffer_barriers) |barrier, *native| {
        native.* = .{
            .buffer = barrier.region.buffer.impl.vk.buffer,
            .size = barrier.region.size,
            .offset = barrier.region.offset,
            .src_stage_mask = stageToNative(barrier.src_stage),
            .dst_stage_mask = stageToNative(barrier.dst_stage),
            .src_access_mask = accessToNative(barrier.src_access),
            .dst_access_mask = accessToNative(barrier.dst_access),
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        };
    }

    encoder.vk.dispatch.cmdPipelineBarrier2(encoder.vk.command_buffer, &.{
        .image_memory_barrier_count = @intCast(image_barriers.len),
        .p_image_memory_barriers = image_barriers.ptr,
        .buffer_memory_barrier_count = @intCast(buffer_barriers.len),
        .p_buffer_memory_barriers = buffer_barriers.ptr,
    });
}

pub fn cmdBeginDebugBlockLabel(encoder: gpu.CommandEncoder, name: [:0]const u8) void {
    if (!encoder.vk.debug) return;
    const info: vk.DebugUtilsLabelEXT = .{
        .p_label_name = name,
        .color = @splat(0),
    };

    encoder.vk.dispatch.cmdBeginDebugUtilsLabelEXT(encoder.vk.command_buffer, &info);
}

pub fn cmdEndDebugBlockLabel(encoder: gpu.CommandEncoder) void {
    if (!encoder.vk.debug) return;
    encoder.vk.dispatch.cmdEndDebugUtilsLabelEXT(encoder.vk.command_buffer);
}

pub const cmdBeginRenderPass = RenderPassEncoder.cmdBegin;
pub const RenderPassEncoder = struct {
    pub const Handle = RenderPassEncoder;

    cmd_encoder: *CommandEncoder,
    image_size: [2]u32,

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

        command_encoder.vk.dispatch.cmdBeginRendering(command_encoder.vk.command_buffer, &.{
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

        return .{ .vk = .{
            .cmd_encoder = command_encoder.vk,
            .image_size = info.image_size,
        } };
    }

    pub fn cmdEnd(encoder: gpu.RenderPassEncoder) void {
        encoder.vk.cmd_encoder.dispatch.cmdEndRendering(encoder.vk.cmd_encoder.command_buffer);
    }

    pub fn cmdBindPipeline(encoder: gpu.RenderPassEncoder, graphics_pipeline: gpu.GraphicsPipeline) void {
        encoder.vk.cmd_encoder.dispatch.cmdBindPipeline(encoder.vk.cmd_encoder.command_buffer, .graphics, graphics_pipeline.vk.pipeline);

        const viewport: vk.Viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(encoder.vk.image_size[0]),
            .height = @floatFromInt(encoder.vk.image_size[1]),
            .min_depth = 0,
            .max_depth = 1,
        };

        encoder.vk.cmd_encoder.dispatch.cmdSetViewport(encoder.vk.cmd_encoder.command_buffer, 0, (&viewport)[0..1]);

        const scissor: vk.Rect2D = .{
            .extent = .{ .width = encoder.vk.image_size[0], .height = encoder.vk.image_size[1] },
            .offset = .{ .x = 0, .y = 0 },
        };

        encoder.vk.cmd_encoder.dispatch.cmdSetScissor(encoder.vk.cmd_encoder.command_buffer, 0, (&scissor)[0..1]);
    }

    pub fn cmdBindVertexBuffer(encoder: gpu.RenderPassEncoder, binding: u32, buffer_region: gpu.Buffer.Region) void {
        const offset = buffer_region.offset;
        encoder.vk.cmd_encoder.dispatch.cmdBindVertexBuffers(
            encoder.vk.cmd_encoder.command_buffer,
            binding,
            (&buffer_region.buffer.impl.vk.buffer)[0..1],
            (&offset)[0..1],
        );
    }

    pub fn cmdBindIndexBuffer(encoder: gpu.RenderPassEncoder, buffer_region: gpu.Buffer.Region, index_type: gpu.RenderPassEncoder.IndexType) void {
        encoder.vk.cmd_encoder.dispatch.cmdBindIndexBuffer(encoder.vk.cmd_encoder.command_buffer, buffer_region.buffer.vk.buffer, buffer_region.offset, switch (index_type) {
            .uint16 => .uint16,
            .uint32 => .uint32,
        });
    }

    pub fn cmdBindResourceSets(encoder: gpu.RenderPassEncoder, pipeline: gpu.GraphicsPipeline, resource_sets: []const gpu.ResourceSet, first: u32) void {
        var arena_obj = encoder.vk.cmd_encoder.arena.promote(encoder.vk.cmd_encoder.gpa);
        defer {
            _ = arena_obj.reset(.retain_capacity);
            encoder.vk.cmd_encoder.arena = arena_obj.state;
        }

        const arena = arena_obj.allocator();
        const natives = ResourceSet.nativesFromSlice(resource_sets, arena) catch {
            encoder.vk.cmd_encoder.out_of_memory = true;
            return;
        };

        encoder.vk.cmd_encoder.dispatch.cmdBindDescriptorSets(
            encoder.vk.cmd_encoder.command_buffer,
            .graphics,
            pipeline.vk.pipeline_layout,
            first,
            natives,
            null,
        );
    }

    pub fn cmdPushConstants(encoder: gpu.RenderPassEncoder, pipeline: gpu.GraphicsPipeline, range: gpu.PushConstantRange, data: [*]const u8) void {
        encoder.vk.cmd_encoder.dispatch.cmdPushConstants(
            encoder.vk.cmd_encoder.command_buffer,
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

    pub fn cmdDraw(encoder: gpu.RenderPassEncoder, info: gpu.RenderPassEncoder.DrawInfo) void {
        if (info.indexed) {
            encoder.vk.cmd_encoder.dispatch.cmdDrawIndexed(encoder.vk.cmd_encoder.command_buffer, info.vertex_count, info.instance_count, 0, @intCast(info.first_vertex), @intCast(info.first_instance));
        } else {
            encoder.vk.cmd_encoder.dispatch.cmdDraw(encoder.vk.cmd_encoder.command_buffer, info.vertex_count, info.instance_count, @intCast(info.first_vertex), @intCast(info.first_instance));
        }
    }

    pub fn cmdDrawIndirect(encoder: gpu.RenderPassEncoder, info: gpu.RenderPassEncoder.DrawIndirectInfo) void {
        std.debug.assert(info.region.offset % 4 == 0);
        std.debug.assert(@as(gpu.Size, info.stride) * info.draw_count <= info.region.size);

        encoder.vk.cmd_encoder.dispatch.cmdDrawIndirect(
            encoder.vk.cmd_encoder.command_buffer,
            info.region.buffer.impl.vk.buffer,
            info.region.offset,
            info.draw_count,
            info.stride,
        );
    }

    pub fn cmdBeginDebugBlockLabel(encoder: gpu.RenderPassEncoder, name: [:0]const u8) void {
        CommandEncoder.cmdBeginDebugBlockLabel(.{ .vk = encoder.vk.cmd_encoder }, name);
    }

    pub fn cmdEndDebugBlockLabel(encoder: gpu.RenderPassEncoder) void {
        CommandEncoder.cmdEndDebugBlockLabel(.{ .vk = encoder.vk.cmd_encoder });
    }
};
