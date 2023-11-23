#pragma once

#include "src/pch.h"
#include "vkInstance.h"
#include "../Shader.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkShader : Shader {
	public:
		vkShader(Instance* instance, const std::vector<uint8>& code);
		virtual ~vkShader();

		virtual Instance* GetInstance();

		VkShaderModule GetNativeShaderModule();
	private:
		VkShaderModule shaderModule;
		vkInstance* instance;
	};

	uint32 GetShaderDataTypeSize(ShaderDataType shaderDataType);
	VkFormat GetShaderDataTypeVkEnum(ShaderDataType shaderDataType);
	uint8 GetShaderDataTypeSlotsUsed(ShaderDataType shaderDataType);
	std::vector<ShaderDataType> UnpackComplexShaderDataTypes(std::vector<ShaderDataType> types);
}