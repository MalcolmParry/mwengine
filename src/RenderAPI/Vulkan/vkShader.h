#pragma once

#include "src/pch.h"
#include "vkDisplay.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkShader {
	public:
		vkShader(vkDisplay* display, const std::vector<uint8>& code);
		vkShader(vkDisplay* display, const std::string& filepath);
		~vkShader();

		VkShaderModule GetNativeShaderModule();
		vkDisplay* GetDisplay();
	private:
		void Create(vkDisplay* display, const std::vector<uint8>& code);

		VkShaderModule shaderModule;
		vkDisplay* display;
	};
}