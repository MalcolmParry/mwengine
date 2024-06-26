#pragma once

#include "src/pch.h"
#include "vkShader.h"
#include "vkInstance.h"
#include "vkBuffer.h"
#include "vkImage.h"
#include "../GraphicsPipeline.h"
#include "vkFramebuffer.h"
#include "vkResourceSet.h"
#include "vkRenderPass.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkGraphicsPipeline : GraphicsPipeline {
	public:
		vkGraphicsPipeline(Instance* instance);
		virtual ~vkGraphicsPipeline();

		virtual void Rebuild();
		virtual void SetDefaults();
		virtual Instance* GetInstance();

		VkPipeline GetNativePipeline();
		VkPipelineLayout GetNativePipelineLayout();
	private:
		void Destroy();

		vkInstance* instance;
		VkPipelineLayout pipelineLayout;
		VkPipeline pipeline;
	};
}