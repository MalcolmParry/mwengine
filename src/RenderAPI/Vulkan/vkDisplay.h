#pragma once

#include "vkInstance.h"
#include "vkImageFormat.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkDisplay {
	public:
		vkDisplay(vkInstance* instance, Window* window = nullptr);
		~vkDisplay();

		void Rebuild();

		vkInstance* GetInstance();
		vkImageFormat* GetImageFormat();
		VkExtent2D GetExtent2D();
		VkSwapchainKHR GetNativeSwapchain();
		VkFramebuffer GetNativeFrameBuffer(uint32 index);
	private:
		void CreateSwapChain();
		void DestroySwapChain();
		VkSurfaceFormatKHR GetSwapSurfaceFormat();
		VkPresentModeKHR GetSwapSurfacePresentMode();
		VkExtent2D GetSwapExtent();

		vkInstance* instance;
		Window* window;
		VkSurfaceKHR surface;
		bool inheritFromInstance;
		vkImageFormat* imageFormat;
		VkFormat format;
		VkExtent2D extent;
		VkSwapchainKHR swapchain;

		std::vector<VkImage> images;
		std::vector<VkImageView> imageViews;
		std::vector<VkFramebuffer> framebuffers;

		VkImage depthImage;
		VkDeviceMemory depthImageMemory;
		VkImageView depthImageView;
	};
}