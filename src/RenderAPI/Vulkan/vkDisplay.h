#pragma once

#include "vkInstance.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkDisplay {
	public:
		vkDisplay(vkInstance* instance, vkPhysicalDevice* physicalDevice);
		~vkDisplay();

		vkInstance* GetInstance();
		vkPhysicalDevice* GetPhysicalDevice();
		VkDevice GetNativeDevice();
		VkRenderPass GetNativeRenderPass();
	private:
		void CreateSwapChain();
		void DestroySwapChain();
		VkSurfaceFormatKHR vkDisplay::GetSwapSurfaceFormat();
		VkPresentModeKHR vkDisplay::GetSwapSurfacePresentMode();
		VkExtent2D vkDisplay::GetSwapExtent();

		vkInstance* instance;
		vkPhysicalDevice* physicalDevice;
		VkDevice device;
		VkRenderPass renderPass;
		VkFormat format;
		VkExtent2D extent;
		VkSwapchainKHR swapchain;
	};
}