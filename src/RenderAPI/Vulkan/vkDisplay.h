#pragma once

#include "vkInstance.h"
#include "vkFrameBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkDisplay {
	public:
		vkDisplay(vkInstance* instance, vkPhysicalDevice* physicalDevice, Window* window = nullptr);
		~vkDisplay();

		void Rebuild();
		vkFrameBuffer* GetFrameBuffer();

		vkInstance* GetInstance();
		vkPhysicalDevice* GetPhysicalDevice();
		VkDevice GetNativeDevice();
		VkRenderPass GetNativeRenderPass();
		VkExtent2D GetExtent2D();
		VkSwapchainKHR GetNativeSwapchain();
	private:
		void CreateSwapChain();
		void DestroySwapChain();
		VkSurfaceFormatKHR vkDisplay::GetSwapSurfaceFormat();
		VkPresentModeKHR vkDisplay::GetSwapSurfacePresentMode();
		VkExtent2D vkDisplay::GetSwapExtent();

		Window* window;
		VkSurfaceKHR surface;
		bool inheritFromInstance;
		vkInstance* instance;
		vkPhysicalDevice* physicalDevice;
		VkDevice device;
		VkRenderPass renderPass;
		VkFormat format;
		VkExtent2D extent;
		VkSwapchainKHR swapchain;
		std::vector<VkImage> images;
		std::vector<VkImageView> imageViews;
		std::vector<vkFrameBuffer*> framebuffers;
	};
}