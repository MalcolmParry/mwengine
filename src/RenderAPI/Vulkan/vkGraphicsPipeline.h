#pragma once

#include "src/pch.h"
#include "vkShader.h"
#include "vkDisplay.h"

namespace mwengine::RenderAPI::Vulkan {
	struct ShaderStage {
		vkShader* shader;
		std::string entry;
	};

	class vkGraphicsPipeline {
	public:
		vkGraphicsPipeline(vkDisplay* display);
		~vkGraphicsPipeline();

		void Rebuild();

		ShaderStage vertexShader;
		ShaderStage fragmentShader;
		uint32 vertexCount;

		vkDisplay* GetDisplay();
		uint32 GetVertexCount();
		VkPipeline GetNativePipeline();
	private:
		void Destroy();

		vkDisplay* display;
		VkPipelineLayout pipelineLayout;
		VkPipeline pipeline;
		uint32 _vertexCount;
	};
}