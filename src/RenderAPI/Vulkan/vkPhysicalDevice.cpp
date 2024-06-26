#include "pch.h"
#include "vkPhysicalDevice.h"

namespace mwengine::RenderAPI::Vulkan {
	vkPhysicalDevice::vkPhysicalDevice(VkPhysicalDevice physicalDevice, VkInstance instance, VkSurfaceKHR surface) {
		this->physicalDevice = physicalDevice;
		this->instance = instance;
		this->surface = surface;
	}

	std::optional<uint32> vkPhysicalDevice::GetGraphicsQueueFamily() {
		uint32_t queueFamilyCount = 0;
		vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nullptr);

		std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
		vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, queueFamilies.data());

		std::optional<uint32> queueFamily;

		for (uint32 i = 0; i < queueFamilyCount; i++) {
			if (queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
				queueFamily = i;

				uint32 presentSupport = false;
				vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, i, surface, &presentSupport);
				if (presentSupport) {
					return i;
				}
			}
		}

		return queueFamily;
	}

	std::optional<uint32> vkPhysicalDevice::GetPresentQueueFamily() {
		uint32_t queueFamilyCount = 0;
		vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nullptr);

		std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
		vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, queueFamilies.data());

		std::optional<uint32> queueFamily;

		for (uint32 i = 0; i < queueFamilyCount; i++) {
			uint32 presentSupport = false;
			vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, i, surface, &presentSupport);
			if (presentSupport) {
				queueFamily = i;

				if (queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
					return i;
				}
			}
		}

		return queueFamily;
	}

	VkPhysicalDevice vkPhysicalDevice::GetNativePhysicalDevice() {
		return physicalDevice;
	}

	VkInstance vkPhysicalDevice::GetNativeInstance() {
		return instance;
	}

	VkSurfaceKHR vkPhysicalDevice::GetNativeSurface() {
		return surface;
	}
}