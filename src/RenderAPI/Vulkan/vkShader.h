#pragma once

#include "src/pch.h"
#include "vkInstance.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkShader {
	public:
		vkShader(vkInstance* instance, const std::vector<uint8>& code);
		vkShader(vkInstance* instance, const std::string& filepath);
		~vkShader();

		VkShaderModule GetNativeShaderModule();
		vkInstance* GetInstance();
	private:
		void Create(vkInstance* instance, const std::vector<uint8>& code);

		VkShaderModule shaderModule;
		vkInstance* instance;
	};

	enum ShaderDataType {
		SHADER_DATA_TYPE_UINT8,
		SHADER_DATA_TYPE_UINT16,
		SHADER_DATA_TYPE_UINT32,
		SHADER_DATA_TYPE_UINT_VEC2,
		SHADER_DATA_TYPE_UINT_VEC3,
		SHADER_DATA_TYPE_UINT_VEC4,
		SHADER_DATA_TYPE_INT8,
		SHADER_DATA_TYPE_INT16,
		SHADER_DATA_TYPE_INT32,
		SHADER_DATA_TYPE_INT_VEC2,
		SHADER_DATA_TYPE_INT_VEC3,
		SHADER_DATA_TYPE_INT_VEC4,
		SHADER_DATA_TYPE_FLOAT,
		SHADER_DATA_TYPE_FLOAT_VEC2,
		SHADER_DATA_TYPE_FLOAT_VEC3,
		SHADER_DATA_TYPE_FLOAT_VEC4
	};

	uint32 GetShaderDataTypeSize(ShaderDataType shaderDataType);
	VkFormat GetShaderDataTypeVkEnum(ShaderDataType shaderDataType);
	uint8 GetShaderDataTypeSlotsUsed(ShaderDataType shaderDataType);
}