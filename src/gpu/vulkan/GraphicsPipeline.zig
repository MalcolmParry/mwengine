const std = @import("std");
const tracy = @import("tracy");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const Shader = @import("Shader.zig");
const ResourceSet = @import("ResourceSet.zig");
const RenderTarget = @import("RenderTarget.zig");

pub const CreateInfo = struct {
    alloc: std.mem.Allocator,
    device: *Device,
    render_target_desc: RenderTarget.Desc,
    shader_set: Shader.Set,
    resource_layouts: []const ResourceSet.Layout,
    framebuffer_size: @Vector(2, u32),
};

_pipeline: vk.Pipeline,
_pipeline_layout: vk.PipelineLayout,

pub fn init(create_info: CreateInfo) !@This() {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    const native_device = create_info.device._device;
    const native_descriptor_set_layouts = try ResourceSet.Layout._nativesFromSlice(create_info.resource_layouts, create_info.alloc);
    defer create_info.alloc.free(native_descriptor_set_layouts);

    // TODO: could be separated into different objects
    const pipeline_layout = try native_device.createPipelineLayout(&.{
        .set_layout_count = @intCast(native_descriptor_set_layouts.len),
        .p_set_layouts = native_descriptor_set_layouts.ptr,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    }, vk_alloc);
    errdefer native_device.destroyPipelineLayout(pipeline_layout, vk_alloc);

    // TODO: add per vertex data
    const shader_stages: [2]vk.PipelineShaderStageCreateInfo = .{
        .{
            .stage = .{ .vertex_bit = true },
            .module = create_info.shader_set.vertex._shader_module,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = create_info.shader_set.pixel._shader_module,
            .p_name = "main",
        },
    };

    const dynamic_states: [2]vk.DynamicState = .{
        .viewport,
        .scissor,
    };
    const extent: vk.Extent2D = .{
        .width = create_info.framebuffer_size[0],
        .height = create_info.framebuffer_size[1],
    };

    const viewport: vk.Viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor: vk.Rect2D = .{
        .extent = extent,
        .offset = .{ .x = 0, .y = 0 },
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
    const vertex_attribute_descriptions = try create_info.alloc.alloc(vk.VertexInputAttributeDescription, create_info.shader_set._per_vertex.len);
    for (create_info.shader_set._per_vertex, 0..) |format, i| {
        vertex_attribute_descriptions[i] = .{
            .binding = 0,
            .location = @intCast(i),
            .format = format,
            .offset = attribute_offset,
        };

        attribute_offset += @intCast(Shader._vkTypeSize(format));
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
            create_info.render_target_desc.color_format._toNative(),
        },
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
        .view_mask = 0, // used for vr and stuff i think
    };

    const pipeline_create_info: vk.GraphicsPipelineCreateInfo = .{
        .subpass = 0,
        .layout = pipeline_layout,
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
            .p_viewports = @ptrCast(&viewport),
            .scissor_count = 1,
            .p_scissors = @ptrCast(&scissor),
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
    var pipeline: vk.Pipeline = .null_handle;
    if (try native_device.createGraphicsPipelines(.null_handle, 1, @ptrCast(&pipeline_create_info), vk_alloc, @ptrCast(&pipeline)) != .success) return error.Unknown;

    return .{
        ._pipeline = pipeline,
        ._pipeline_layout = pipeline_layout,
    };
}

pub fn deinit(this: *@This(), device: *Device) void {
    const zone = tracy.Zone.begin(.{
        .src = @src(),
    });
    defer zone.end();

    const vk_alloc: ?*vk.AllocationCallbacks = null;
    device._device.destroyPipeline(this._pipeline, vk_alloc);
    device._device.destroyPipelineLayout(this._pipeline_layout, vk_alloc);
}
