#pragma once

#include "vkInstance.h"
#include "../Display.h"
#include "vkFramebuffer.h"
#include "vkWaitObjects.h"
#include "vkRenderPass.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkDisplay : Display {
	public:
		vkDisplay(Instance* instance, Window* window = nullptr);
		virtual ~vkDisplay();

		virtual void Rebuild();

		virtual Instance* GetInstance();
		virtual void SetRenderPass(RenderPass* renderPass);
		virtual uint32 GetNextFramebufferIndex(Semaphore* signalSemaphore, Fence* signalFence);
		virtual Framebuffer* GetFramebuffer(uint32 i);
		virtual void PresentFramebuffer(uint32 framebufferIndex, Semaphore* waitSemaphore);

		VkExtent2D GetExtent2D();
		VkSwapchainKHR GetNativeSwapchain();
		VkFormat GetNativeFormat();
	private:
		void CreateSwapChain();
		void DestroySwapChain();
		void DestroyFramebuffers();
		VkSurfaceFormatKHR GetSwapSurfaceFormat();
		VkPresentModeKHR GetSwapSurfacePresentMode();
		VkExtent2D GetSwapExtent();

		vkInstance* instance;
		Window* window;
		VkSurfaceKHR surface;
		bool inheritFromInstance;
		vkRenderPass* renderPass;
		VkFormat format;
		VkExtent2D extent;
		VkSwapchainKHR swapchain;

		std::vector<VkImage> images;
		std::vector<VkImageView> imageViews;
		std::vector<Framebuffer*> framebuffers;

		VkImage depthImage;
		VkDeviceMemory depthImageMemory;
		VkImageView depthImageView;
	};
}