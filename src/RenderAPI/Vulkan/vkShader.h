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
}