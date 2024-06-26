#include "pch.h"

#if (MW_PLAFORM == WINDOWS)

#include "WindowsVulkan.h"

namespace mwengine::RenderAPI::Vulkan {
	std::vector<const char*> GetRequiredExtentions() {
		return {
			"VK_KHR_surface",
			"VK_KHR_win32_surface"
		};
	}

	VkSurfaceKHR CreateSurface(Window* window, VkInstance instance) {
		VkSurfaceKHR surface;

		VkWin32SurfaceCreateInfoKHR createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
		createInfo.hwnd = (HWND) window->GetHandle();
		createInfo.hinstance = GetModuleHandle(nullptr);

		if (vkCreateWin32SurfaceKHR(instance, &createInfo, nullptr, &surface) != VK_SUCCESS) {
			MW_ERROR("Vulkan: Failed to create window surface.");
		}

		return surface;
	}
}

#endif