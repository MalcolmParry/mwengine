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

    // TODO: add per vertex data
    const shader_stages: [2]vk.PipelineShaderStageCreateInfo = .{
        .{
            .stage = .{ .vertex_bit = true },
            .module = info.shader_set.vk.vertex.vk.shader_module,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = info.shader_set.vk.pixel.vk.shader_module,
            .p_name = "main",
        },
    };

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

    var attribute_offset: u32 = 0;
    const vertex_attribute_descriptions = try info.alloc.alloc(vk.VertexInputAttributeDescription, info.shader_set.vk.per_vertex.len);
    defer info.alloc.free(vertex_attribute_descriptions);
    for (info.shader_set.vk.per_vertex, 0..) |format, i| {
        vertex_attribute_descriptions[i] = .{
            .binding = 0,
            .location = @intCast(i),
            .format = format,
            .offset = attribute_offset,
        };

        attribute_offset += @intCast(Shader.vkTypeSize(format));
    }

    const vertex_bindings: [1]vk.VertexInputBindingDescription = .{
        .{
            .binding = 0,
            .input_rate = .vertex,
            .stride = attribute_offset,
        },
    };

    const rendering_create_info: vk.PipelineRenderingCreateInfo = .{
        .color_attachment_count = 1,
        .p_color_attachment_formats = &.{
            Image.formatToNative(info.render_target_desc.color_format),
        },
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
        .view_mask = 0, // used for vr and stuff i think
    };

    const pipeline_create_info: vk.GraphicsPipelineCreateInfo = .{
        .subpass = 0,
        .layout = this.pipeline_layout,
        .render_pass = .null_handle,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
        .stage_count = shader_stages.len,
        .p_stages = &shader_stages,
        .p_tessellation_state = null,
        .p_vertex_input_state = &.{
            .vertex_attribute_description_count = @intCast(vertex_attribute_descriptions.len),
            .p_vertex_attribute_descriptions = vertex_attribute_descriptions.ptr,
            .vertex_binding_description_count = vertex_bindings.len,
            .p_vertex_binding_descriptions = @ptrCast(&vertex_bindings),
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
            .cull_mode = .{},
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
            .depth_test_enable = .false,
            .depth_write_enable = .false,
            .depth_compare_op = .less,
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
