#include "pch.h"
#include "vkShader.h"

namespace mwengine::RenderAPI::Vulkan {
	vkShader::vkShader(vkInstance* instance, const std::vector<uint8>& code) {
		Create(instance, code);
	}

	vkShader::vkShader(vkInstance* instance, const std::string& filepath) {
		std::ifstream file(filepath, std::ios::ate | std::ios::binary);
		if (!file.is_open())
			MW_ERROR("Shader file failed to open.");

		uint32 size = (uint32) file.tellg();
		std::vector<uint8> code(size);
		file.seekg(0);
		file.read((char*) code.data(), size);
		file.close();
		Create(instance, code);
	}
	
	vkShader::~vkShader() {
		vkDestroyShaderModule(instance->GetNativeDevice(), shaderModule, nullptr);
	}

	VkShaderModule vkShader::GetNativeShaderModule() {
		return shaderModule;
	}

	vkInstance* vkShader::GetInstance() {
		return instance;
	}
	
	void vkShader::Create(vkInstance* instance, const std::vector<uint8>& code) {
		this->instance = instance;

		VkShaderModuleCreateInfo createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
		createInfo.codeSize = code.size();
		createInfo.pCode = (uint32*) code.data();
		
		if (vkCreateShaderModule(instance->GetNativeDevice(), &createInfo, nullptr, &shaderModule) != VK_SUCCESS) {
			MW_ERROR("Failed to create shader.");
		}
	}
}