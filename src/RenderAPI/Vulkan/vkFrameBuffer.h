#pragma once

#include "src/pch.h"
#include "vulkan/vulkan.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkFrameBuffer {
	public:
		vkFrameBuffer(VkDevice device, VkExtent2D extent, VkImageView imageView, VkRenderPass renderPass, uint32 swapchainImageIndex = 0);
		~vkFrameBuffer();

		VkFramebuffer GetNativeFrameBuffer();
		VkExtent2D GetNativeExtent();
		uint32 GetSwapchainImageIndex();
	private:
		VkFramebuffer frameBuffer;
		VkDevice device;
		VkExtent2D extent;
		uint32 swapchainImageIndex;
	};
}