const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const Image = @import("Image.zig");

pub const Desc = Descriptor;
pub const Descriptor = struct {
    _render_pass: vk.RenderPass,

    pub fn init(device: *Device, image_format: Image.Format) !@This() {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        const attachments: [1]vk.AttachmentDescription = .{
            .{
                .format = image_format._toNative(),
                .samples = .{
                    .@"1_bit" = true,
                },
                .load_op = .clear,
                .store_op = .store,
                .stencil_load_op = .dont_care,
                .stencil_store_op = .dont_care,
                .initial_layout = .undefined,
                .final_layout = .present_src_khr,
            },
        };

        const color_attachment_ref: vk.AttachmentReference = .{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };

        const subpass: vk.SubpassDescription = .{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&color_attachment_ref),
            .p_depth_stencil_attachment = null,
        };

        const subpass_dep: vk.SubpassDependency = .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{
                .color_attachment_output_bit = true,
                .early_fragment_tests_bit = true,
            },
            .src_access_mask = .{},
            .dst_stage_mask = .{
                .color_attachment_output_bit = true,
                .early_fragment_tests_bit = true,
            },
            .dst_access_mask = .{
                .color_attachment_write_bit = true,
                .depth_stencil_attachment_write_bit = true,
            },
        };

        const render_pass = try device._device.createRenderPass(&.{
            .attachment_count = attachments.len,
            .p_attachments = &attachments,
            .subpass_count = 1,
            .p_subpasses = @ptrCast(&subpass),
            .dependency_count = 1,
            .p_dependencies = @ptrCast(&subpass_dep),
        }, vk_alloc);

        return .{ ._render_pass = render_pass };

        // const depthAttachment: c.VkAttachmentDescription = .{
        //     .format = try vk.utils.getDepthFormat(display.device.physical._device),
        //     .samples = c.VK_SAMPLE_COUNT_1_BIT,
        //     .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        //     .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        //     .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        //     .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        //     .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        //     .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        // };
        //
        // const depthAttachmentRef: c.VkAttachmentReference = .{
        //     .attachment = 1,
        //     .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        // };
    }

    pub fn deinit(this: *@This(), device: *Device) void {
        const vk_alloc: ?*vk.AllocationCallbacks = null;
        device._device.destroyRenderPass(this._render_pass, vk_alloc);
    }
};
