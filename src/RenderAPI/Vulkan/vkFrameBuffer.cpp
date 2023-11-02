#include "pch.h"
#include "vkFrameBuffer.h"
#include "vkDisplay.h"

namespace mwengine::RenderAPI::Vulkan {
	vkFrameBuffer::vkFrameBuffer(VkDevice device, VkExtent2D extent, VkImageView imageView, VkRenderPass renderPass, uint32 swapchainImageIndex) {
		this->device = device;
		this->extent = extent;
		this->swapchainImageIndex = swapchainImageIndex;

		VkImageView attachments[] = {
			imageView
		};
		
		VkFramebufferCreateInfo framebufferInfo {};
		framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
		framebufferInfo.renderPass = renderPass;
		framebufferInfo.attachmentCount = 1;
		framebufferInfo.pAttachments = attachments;
		framebufferInfo.width = extent.width;
		framebufferInfo.height = extent.height;
		framebufferInfo.layers = 1;

		if (vkCreateFramebuffer(device, &framebufferInfo, nullptr, &frameBuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to create framebuffer.");
		}
	}

	vkFrameBuffer::~vkFrameBuffer() {
		vkDestroyFramebuffer(device, frameBuffer, nullptr);
	}

	VkFramebuffer vkFrameBuffer::GetNativeFrameBuffer() {
		return frameBuffer;
	}

	VkExtent2D vkFrameBuffer::GetNativeExtent() {
		return extent;
	}

	uint32 vkFrameBuffer::GetSwapchainImageIndex() {
		return swapchainImageIndex;
	}
}