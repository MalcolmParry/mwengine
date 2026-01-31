const std = @import("std");
const gpu = @import("../../gpu.zig");
const vk = @import("vulkan");
const Shader = @import("Shader.zig");
const ResourceSet = @import("ResourceSet.zig");
const Image = @import("Image.zig");

const GraphicsPipeline = @This();
pub const Handle = *GraphicsPipeline;

pipeline: vk.Pipeline,
pipeline_layout: vk.PipelineLayout,

pub fn init(device: gpu.Device, info: gpu.GraphicsPipeline.CreateInfo) !gpu.GraphicsPipeline {
    const this = try info.alloc.create(GraphicsPipeline);
    errdefer info.alloc.destroy(this);

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const native_device = device.vk.device;
    const native_descriptor_set_layouts = try ResourceSet.Layout.nativesFromSlice(info.resource_layouts, info.alloc);
    defer info.alloc.free(native_descriptor_set_layouts);

    const native_push_constant_ranges = try info.alloc.alloc(vk.PushConstantRange, info.push_constant_ranges.len);
    defer info.alloc.free(native_push_constant_ranges);
    for (native_push_constant_ranges, info.push_constant_ranges) |*native, range| {
        native.* = .{
            .stage_flags = .{
                .vertex_bit = range.stages.vertex,
                .fragment_bit = range.stages.pixel,
            },
            .offset = range.offset,
            .size = range.size,
        };
    }

    // TODO: could be separated into different objects
    this.pipeline_layout = try native_device.createPipelineLayout(&.{
        .set_layout_count = @intCast(native_descriptor_set_layouts.len),
        .p_set_layouts = native_descriptor_set_layouts.ptr,
        .push_constant_range_count = @intCast(native_push_constant_ranges.len),
        .p_push_constant_ranges = native_push_constant_ranges.ptr,
    }, vk_alloc);
    errdefer native_device.destroyPipelineLayout(this.pipeline_layout, vk_alloc);

    const shader_stages = try info.alloc.alloc(vk.PipelineShaderStageCreateInfo, info.shaders.len);
    defer info.alloc.free(shader_stages);

    for (shader_stages, info.shaders) |*native, shader| {
        native.* = .{
            .stage = shader.vk.stage,
            .module = shader.vk.shader_module,
            .p_name = "main",
        };
    }

    var vert_atrib_desc_count: usize = 0;
    for (info.vertex_input_bindings) |binding| {
        for (binding.fields) |field| {
            vert_atrib_desc_count += switch (field.type) {
                .float32x4x4 => 4,
                else => 1,
            };
        }
    }

    var vert_atrib_descs: std.ArrayList(vk.VertexInputAttributeDescription) = try .initCapacity(info.alloc, vert_atrib_desc_count);
    defer vert_atrib_descs.deinit(info.alloc);

    const vert_bind_descs = try info.alloc.alloc(vk.VertexInputBindingDescription, info.vertex_input_bindings.len);
    defer info.alloc.free(vert_bind_descs);

    for (info.vertex_input_bindings, vert_bind_descs) |bind, *native| {
        var stride: usize = 0;
        var loc: u32 = 0;

        for (bind.fields) |field| {
            const alignment = field.alignment orelse field.type.alignment();
            stride = alignment.forward(stride);

            if (field.type == .float32x4x4) {
                for (0..4) |_| {
                    vert_atrib_descs.appendAssumeCapacity(.{
                        .binding = bind.binding,
                        .location = loc,
                        .format = .r32g32b32a32_sfloat,
                        .offset = @intCast(stride),
                    });

                    loc += 1;
                    stride += 4;
                }

                continue;
            }

            vert_atrib_descs.appendAssumeCapacity(.{
                .binding = bind.binding,
                .location = loc,
                .format = Shader.dataTypeToNative(field.type),
                .offset = @intCast(stride),
            });

            stride += field.type.size();
            loc += 1;
        }

        native.* = .{
            .binding = bind.binding,
            .input_rate = switch (bind.rate) {
                .per_vertex => .vertex,
                .per_instance => .instance,
            },
            .stride = @intCast(stride),
        };
    }

    const dynamic_states: [2]vk.DynamicState = .{
        .viewport,
        .scissor,
    };

    const color_blend_attachment: vk.PipelineColorBlendAttachmentState = .{
        .color_write_mask = .{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true,
        },
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
    };

    const rendering_create_info: vk.PipelineRenderingCreateInfo = .{
        .color_attachment_count = 1,
        .p_color_attachment_formats = &.{
            Image.formatToNative(info.render_target_desc.color_format),
        },
        .depth_attachment_format = Image.formatToNative(info.render_target_desc.depth_format orelse .unknown),
        .stencil_attachment_format = .undefined,
        .view_mask = 0, // used for vr and stuff i think
    };

    const pipeline_create_info: vk.GraphicsPipelineCreateInfo = .{
        .subpass = 0,
        .layout = this.pipeline_layout,
        .render_pass = .null_handle,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
        .stage_count = @intCast(shader_stages.len),
        .p_stages = shader_stages.ptr,
        .p_tessellation_state = null,
        .p_vertex_input_state = &.{
            .vertex_attribute_description_count = @intCast(vert_atrib_desc_count),
            .p_vertex_attribute_descriptions = vert_atrib_descs.items.ptr,
            .vertex_binding_description_count = @intCast(vert_bind_descs.len),
            .p_vertex_binding_descriptions = vert_bind_descs.ptr,
        },
        .p_input_assembly_state = &.{
            .topology = .triangle_list, // TODO: allow more options
            .primitive_restart_enable = .false, // TODO: implement (allows you to seperate triangle strip)
        },
        .p_viewport_state = &.{
            .viewport_count = 1,
            .p_viewports = null,
            .scissor_count = 1,
            .p_scissors = null,
        },
        .p_rasterization_state = &.{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = switch (info.cull_mode) {
                .none => .{},
                .front => .{ .front_bit = true },
                .back => .{ .back_bit = true },
            },
            .front_face = .counter_clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        },
        .p_multisample_state = &.{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        },
        .p_depth_stencil_state = &.{
            .depth_test_enable = if (info.depth_mode.testing) .true else .false,
            .depth_write_enable = if (info.depth_mode.writing) .true else .false,
            .depth_compare_op = switch (info.depth_mode.compare_op) {
                .never => .never,
                .less => .less,
                .equal => .equal,
                .less_or_equal => .less_or_equal,
                .greater => .greater,
                .not_equal => .not_equal,
                .greater_or_equal => .greater_or_equal,
                .always => .always,
            },
            .depth_bounds_test_enable = .false,
            .min_depth_bounds = 0,
            .max_depth_bounds = 1,
            .stencil_test_enable = .false,
            .front = .{
                .fail_op = .keep,
                .pass_op = .replace,
                .depth_fail_op = .keep,
                .compare_op = .always,
                .compare_mask = 0xff,
                .write_mask = 0xff,
                .reference = 1,
            },
            .back = .{
                .fail_op = .keep,
                .pass_op = .replace,
                .depth_fail_op = .keep,
                .compare_op = .always,
                .compare_mask = 0xff,
                .write_mask = 0xff,
                .reference = 1,
            },
        },
        .p_color_blend_state = &.{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_blend_attachment),
            .blend_constants = .{ 0, 0, 0, 0 },
        },
        .p_dynamic_state = &.{
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        },
        .p_next = @ptrCast(&rendering_create_info),
    };

    // the only way for pipeline creation to return a non zig error is
    // if we requested lazy compilation in flags
    this.pipeline = .null_handle;
    if (try native_device.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_create_info), vk_alloc, @ptrCast(&this.pipeline)) != .success) return error.Unknown;

    return .{ .vk = this };
}

pub fn deinit(this: gpu.GraphicsPipeline, device: gpu.Device, alloc: std.mem.Allocator) void {
    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device.vk.device.destroyPipeline(this.vk.pipeline, vk_alloc);
    device.vk.device.destroyPipelineLayout(this.vk.pipeline_layout, vk_alloc);
    alloc.destroy(this.vk);
}
