#pragma once

#include "src/pch.h"
#include "vkInstance.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkImageFormat {
	public:
		vkImageFormat(vkInstance* instance, VkRenderPass renderPass, VkExtent2D extent);
		~vkImageFormat();

		glm::uvec2 GetSize();
		VkRenderPass GetNativeRenderPass();
	private:
		vkInstance* instance;
		VkRenderPass renderPass;
		glm::uvec2 size;
	};
}