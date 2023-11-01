#pragma once

#include "src/pch.h"
#include "vulkan/vulkan.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkInstance;

	class vkPhysicalDevice {
	public:
		vkPhysicalDevice(VkPhysicalDevice physicalDevice, VkInstance instance, VkSurfaceKHR surface);

		std::optional<uint32> GetGraphicsQueueFamily();
		std::optional<uint32> GetPresentQueueFamily();

		VkPhysicalDevice GetNativePhysicalDevice();
		VkInstance GetNativeInstance();
		VkSurfaceKHR GetNativeSurface();
	private:
		VkPhysicalDevice physicalDevice;
		VkInstance instance;
		VkSurfaceKHR surface;
	};
}