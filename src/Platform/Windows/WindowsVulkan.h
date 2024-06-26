#pragma once

#define NOMINMAX
#define VK_USE_PLATFORM_WIN32_KHR
#include "vulkan/vulkan.h"
#include "src/Window.h"
#include <vector>

namespace mwengine::RenderAPI::Vulkan {
	std::vector<const char*> GetRequiredExtentions();
	VkSurfaceKHR CreateSurface(Window* window, VkInstance instance);
}