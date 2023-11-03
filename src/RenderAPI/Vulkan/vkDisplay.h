#pragma once

#include "vkInstance.h"
#include "vkFrameBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkDisplay {
	public:
		vkDisplay(vkInstance* instance, Window* window = nullptr);
		~vkDisplay();

		void Rebuild();
		vkFrameBuffer* GetFrameBuffer();

		vkInstance* GetInstance();
		VkRenderPass GetNativeRenderPass();
		VkExtent2D GetExtent2D();
		VkSwapchainKHR GetNativeSwapchain();
	private:
		void CreateSwapChain();
		void DestroySwapChain();
		VkSurfaceFormatKHR GetSwapSurfaceFormat();
		VkPresentModeKHR GetSwapSurfacePresentMode();
		VkExtent2D GetSwapExtent();

		Window* window;
		VkSurfaceKHR surface;
		bool inheritFromInstance;
		vkInstance* instance;
		VkRenderPass renderPass;
		VkFormat format;
		VkExtent2D extent;
		VkSwapchainKHR swapchain;
		std::vector<VkImage> images;
		std::vector<VkImageView> imageViews;
		std::vector<vkFrameBuffer*> framebuffers;
	};
}