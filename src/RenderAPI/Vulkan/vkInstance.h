#pragma once

#include "src/pch.h"
#include "vulkan/vulkan.h"
#include "src/Window.h"
#include "vkPhysicalDevice.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkInstance {
	public:
		vkInstance(Window* window, const std::string& appName, uint32 appVersion, bool debug);
		~vkInstance();

		std::vector<vkPhysicalDevice*> GetPhysicalDevices();
		vkPhysicalDevice* GetOptimalPhysicalDevice();
		void SetPhysicalDevice(vkPhysicalDevice* physicalDevice);

		Window* GetWindow();
		VkInstance GetNativeInstance();
		VkDebugUtilsMessengerEXT GetNativeDebugMessenger();
		VkSurfaceKHR GetNativeSurface();
		vkPhysicalDevice* GetPhysicalDevice();
		VkDevice GetNativeDevice();
	private:
		Window* window;
		VkInstance instance;
		VkDebugUtilsMessengerEXT debugMessenger;
		VkSurfaceKHR surface;
		vkPhysicalDevice* physicalDevice;
		VkDevice device;
		bool debug;
		std::vector<vkPhysicalDevice*> physicalDevices;
	};
}