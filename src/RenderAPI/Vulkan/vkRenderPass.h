#pragma once

#include "../RenderPass.h"
#include "vkInstance.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkDisplay;

	class vkRenderPass : RenderPass {
	public:
		vkRenderPass(Instance* instance, Display* display = nullptr);
		virtual ~vkRenderPass();

		virtual Instance* GetInstance();
		VkRenderPass GetNativeRenderPass();
	private:
		vkInstance* instance;
		VkRenderPass renderPass;
	};
}