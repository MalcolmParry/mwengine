#pragma once

#include "src/pch.h"
#include "vkShader.h"
#include "vkInstance.h"
#include "vkImageFormat.h"
#include "vkBuffer.h"
#include "vkImage.h"
#include "../GraphicsPipeline.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkGraphicsPipeline {
	public:
		vkGraphicsPipeline(Instance* instance);
		virtual ~vkGraphicsPipeline();

		virtual void Rebuild();
		virtual void SetDefaults();
		virtual Instance* GetInstance();

		vkImageFormat* imageFormat;
		std::vector<ShaderDataType> vertexSpecification;
		uint32 indexCount;
		std::vector<ShaderDataType> instanceSpecification;
		uint32 instanceCount;
		bool hasUniformBuffer;
		uint32 textureCount;
		CullingMode cullingMode;
		bool depthTesting;
		ShaderStage vertexShader;
		ShaderStage fragmentShader;

		VkPipeline GetNativePipeline();
		VkPipelineLayout GetNativePipelineLayout();
		VkDescriptorSet GetNativeDescriptorSet();
	private:
		void Destroy();

		vkInstance* instance;
		VkDescriptorSetLayout descriptorSetLayout;
		VkDescriptorPool descriptorPool;
		VkDescriptorSet descriptorSet;
		VkPipelineLayout pipelineLayout;
		VkPipeline pipeline;

		bool oldHasDescriptorSets;
	};
}