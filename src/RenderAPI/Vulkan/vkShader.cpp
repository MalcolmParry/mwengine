#include "pch.h"
#include "vkShader.h"

namespace mwengine::RenderAPI::Vulkan {
	vkShader::vkShader(vkDisplay* display, const std::vector<uint8>& code) {
		Create(display, code);
	}

	vkShader::vkShader(vkDisplay* display, const std::string& filepath) {
		std::ifstream file(filepath, std::ios::ate | std::ios::binary);
		if (!file.is_open())
			MW_ERROR("Shader file failed to open.");

		uint32 size = (uint32) file.tellg();
		std::vector<uint8> code(size);
		file.seekg(0);
		file.read((char*) code.data(), size);
		file.close();
		Create(display, code);
	}
	
	vkShader::~vkShader() {
		vkDestroyShaderModule(display->GetNativeDevice(), shaderModule, nullptr);
	}

	VkShaderModule vkShader::GetNativeShaderModule() {
		return shaderModule;
	}

	vkDisplay* vkShader::GetDisplay() {
		return display;
	}
	
	void vkShader::Create(vkDisplay* display, const std::vector<uint8>& code) {
		this->display = display;

		VkShaderModuleCreateInfo createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
		createInfo.codeSize = code.size();
		createInfo.pCode = (uint32*) code.data();
		
		if (vkCreateShaderModule(display->GetNativeDevice(), &createInfo, nullptr, &shaderModule) != VK_SUCCESS) {
			MW_ERROR("Failed to create shader.");
		}
	}
}