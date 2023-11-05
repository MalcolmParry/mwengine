#pragma once

#include "src/pch.h"
#include "vkShader.h"
#include "vkInstance.h"
#include "vkImageFormat.h"
#include "vkBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	struct ShaderStage {
		vkShader* shader;
		std::string entry;
	};

	class vkGraphicsPipeline {
	public:
		vkGraphicsPipeline(vkInstance* instance);
		~vkGraphicsPipeline();

		void Rebuild();

		vkBuffer* vertexBuffer;
		std::vector<ShaderDataType> vertexSpecification;
		vkBuffer* indexBuffer;
		uint32 indexCount;
		vkBuffer* instanceBuffer;
		std::vector<ShaderDataType> instanceSpecification;
		uint32 instanceCount;
		vkImageFormat* imageFormat;
		ShaderStage vertexShader;
		ShaderStage fragmentShader;

		vkInstance* GetInstance();
		VkPipeline GetNativePipeline();
	private:
		void Destroy();

		vkInstance* instance;
		VkPipelineLayout pipelineLayout;
		VkPipeline pipeline;
	};
}