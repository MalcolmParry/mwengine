#include "pch.h"
#include "vkDisplay.h"
#include "vkPlatform.h"
#include "vkUtils.h"

namespace mwengine::RenderAPI::Vulkan {
	const std::vector<const char*> requiredDeviceExtensions = {
		VK_KHR_SWAPCHAIN_EXTENSION_NAME
	};
	
	vkDisplay::vkDisplay(Instance* instance, Window* window) {
		if (window == nullptr) {
			inheritFromInstance = true;
			surface = ((vkInstance*) instance)->GetNativeSurface();
			this->window = window;
		} else {
			inheritFromInstance = false;
			this->window = window;
			surface = CreateSurface(window, ((vkInstance*) instance)->GetNativeInstance());
		}

		this->instance = (vkInstance*) instance;
		this->format = GetSwapSurfaceFormat().format;
		this->swapchain = nullptr;

		CreateSwapChain();
	}

	vkDisplay::~vkDisplay() {
		DestroySwapChain();

		vkDestroySwapchainKHR(instance->GetNativeDevice(), swapchain, nullptr);
		if (!inheritFromInstance)
			vkDestroySurfaceKHR(instance->GetNativeInstance(), surface, nullptr);
	}

	void vkDisplay::Rebuild() {
		vkDeviceWaitIdle(instance->GetNativeDevice());

		DestroySwapChain();
		CreateSwapChain();

		if (renderPass != nullptr) {
			SetRenderPass((RenderPass*) renderPass);
		}
	}

	Instance* vkDisplay::GetInstance() {
		return (Instance*) instance;
	}

	void vkDisplay::SetRenderPass(RenderPass* renderPass) {
		DestroyFramebuffers();
		this->renderPass = (vkRenderPass*) renderPass;
		
		framebuffers.resize(imageViews.size());
		for (uint32 i = 0; i < imageViews.size(); i++) {
			framebuffers[i] = (Framebuffer*) new vkFramebuffer((Instance*) instance, { extent.width, extent.height }, imageViews[i], depthImageView, renderPass);
		}
	}

	uint32 vkDisplay::GetNextFramebufferIndex(Semaphore* signalSemaphore, Fence* signalFence) {
		VkSemaphore nativeSignalSemaphore = nullptr;
		if (signalSemaphore != nullptr)
			nativeSignalSemaphore = ((vkSemaphore*) signalSemaphore)->GetNativeSemaphore();

		VkFence nativeSignalFence = nullptr;
		if (signalFence != nullptr)
			nativeSignalFence = ((vkFence*) signalFence)->GetNativeFence();

		uint32 index;
		VkResult result = vkAcquireNextImageKHR(instance->GetNativeDevice(), swapchain, 1'000'000'000, nativeSignalSemaphore, nativeSignalFence, &index);
		switch (result) {
		case VK_SUCCESS:
		case VK_SUBOPTIMAL_KHR:
			return index;
		case VK_ERROR_OUT_OF_DATE_KHR:
			return NoImage;
		default:
			MW_ERROR("Failed to aquire swapchain frambuffer index.");
			return NoImage;
		}
	}

	Framebuffer* vkDisplay::GetFramebuffer(uint32 i) {
		return framebuffers[i];
	}

	void vkDisplay::PresentFramebuffer(uint32 framebufferIndex, Semaphore* waitSemaphore) {
		VkSemaphore nativeWaitSemaphore = nullptr;
		if (waitSemaphore != nullptr)
			nativeWaitSemaphore = ((vkSemaphore*) waitSemaphore)->GetNativeSemaphore();

		VkPresentInfoKHR presentInfo {};
		presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
		presentInfo.waitSemaphoreCount = (nativeWaitSemaphore != nullptr) ? 1 : 0;
		presentInfo.pWaitSemaphores = &nativeWaitSemaphore;
		presentInfo.swapchainCount = 1;
		presentInfo.pSwapchains = &swapchain;
		presentInfo.pImageIndices = &framebufferIndex;
		presentInfo.pResults = nullptr;

		VkQueue presentQueue;
		vkGetDeviceQueue(instance->GetNativeDevice(), ((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetPresentQueueFamily().value(), 0, &presentQueue);

		vkQueuePresentKHR(presentQueue, &presentInfo);
	}

	VkExtent2D vkDisplay::GetExtent2D() {
		return extent;
	}

	VkSwapchainKHR vkDisplay::GetNativeSwapchain() {
		return swapchain;
	}

	VkFormat vkDisplay::GetNativeFormat() {
		return format;
	}

	void vkDisplay::CreateSwapChain() {
		VkSwapchainKHR oldSwapChain = swapchain;

		VkSurfaceCapabilitiesKHR capabilities;
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetNativePhysicalDevice(), surface, &capabilities);

		uint32 imageCount = capabilities.minImageCount + 1;
		if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount) {
			uint32 imageCount = capabilities.maxImageCount;
		}

		VkSurfaceFormatKHR imageFormat = GetSwapSurfaceFormat();
		format = imageFormat.format;
		extent = GetSwapExtent();

		VkSwapchainCreateInfoKHR createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
		createInfo.surface = surface;
		createInfo.minImageCount = imageCount;
		createInfo.imageFormat = imageFormat.format;
		createInfo.imageColorSpace = imageFormat.colorSpace;
		createInfo.imageExtent = extent;
		createInfo.imageArrayLayers = 1;
		createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

		uint32 queueFamilyIndices[] = { ((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetGraphicsQueueFamily().value(), ((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetPresentQueueFamily().value() };

		if (queueFamilyIndices[0] != queueFamilyIndices[1]) {
			createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT;
			createInfo.queueFamilyIndexCount = 2;
			createInfo.pQueueFamilyIndices = queueFamilyIndices;
		} else {
			createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
			createInfo.queueFamilyIndexCount = 0;
			createInfo.pQueueFamilyIndices = nullptr;
		}

		createInfo.preTransform = capabilities.currentTransform;
		createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
		createInfo.presentMode = GetSwapSurfacePresentMode();
		createInfo.clipped = true;
		createInfo.oldSwapchain = oldSwapChain;

		if (vkCreateSwapchainKHR(instance->GetNativeDevice(), &createInfo, nullptr, &swapchain) != VK_SUCCESS) {
			MW_ERROR("Failed to create swapchain.");
		}

		VkFormat depthFormat = Utils::GetDepthFormat(instance);
		Utils::CreateImage(
			instance,
			Math::UInt2(extent.width, extent.height),
			depthFormat,
			VK_IMAGE_TILING_OPTIMAL,
			VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
			VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
			depthImage,
			depthImageMemory
		);

		depthImageView = Utils::CreateImageView(instance, depthImage, depthFormat, VK_IMAGE_ASPECT_DEPTH_BIT);

		uint32 swapImageCount;
		vkGetSwapchainImagesKHR(instance->GetNativeDevice(), swapchain, &swapImageCount, nullptr);
		images.resize(swapImageCount);
		vkGetSwapchainImagesKHR(instance->GetNativeDevice(), swapchain, &swapImageCount, images.data());

		imageViews.resize(images.size());
		for (uint32 i = 0; i < images.size(); i++) {
			imageViews[i] = Utils::CreateImageView(instance, images[i], format, VK_IMAGE_ASPECT_COLOR_BIT);
		}

		framebuffers.resize(0);

		if (oldSwapChain != nullptr)
			vkDestroySwapchainKHR(instance->GetNativeDevice(), oldSwapChain, nullptr);
	}

	void vkDisplay::DestroySwapChain() {
		DestroyFramebuffers();

		vkDestroyImageView(instance->GetNativeDevice(), depthImageView, nullptr);
		vkDestroyImage(instance->GetNativeDevice(), depthImage, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), depthImageMemory, nullptr);

		for (VkImageView imageView : imageViews) {
			vkDestroyImageView(instance->GetNativeDevice(), imageView, nullptr);
		}
	}

	void vkDisplay::DestroyFramebuffers() {
		for (Framebuffer* framebuffer : framebuffers) {
			delete framebuffer;
		}
	}

	VkSurfaceFormatKHR vkDisplay::GetSwapSurfaceFormat() {
		uint32 formatCount;
		std::vector<VkSurfaceFormatKHR> formats;
		vkGetPhysicalDeviceSurfaceFormatsKHR(((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetNativePhysicalDevice(), surface, &formatCount, nullptr);

		if (formatCount != 0) {
			formats.resize(formatCount);
			vkGetPhysicalDeviceSurfaceFormatsKHR(((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetNativePhysicalDevice(), surface, &formatCount, formats.data());

			for (const auto& format : formats) {
				if (format.format == VK_FORMAT_B8G8R8A8_SRGB && format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
					return format;
				}
			}

			return formats[0];
		}

		return {};
	}

	VkPresentModeKHR vkDisplay::GetSwapSurfacePresentMode() {
		uint32 modeCount;
		std::vector<VkPresentModeKHR> modes;
		vkGetPhysicalDeviceSurfacePresentModesKHR(((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetNativePhysicalDevice(), surface, &modeCount, nullptr);

		if (modeCount != 0) {
			modes.resize(modeCount);
			vkGetPhysicalDeviceSurfacePresentModesKHR(((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetNativePhysicalDevice(), surface, &modeCount, modes.data());

			for (const auto& mode : modes) {
				if (mode == VK_PRESENT_MODE_MAILBOX_KHR) {
					return mode;
				}
			}
		}

		return VK_PRESENT_MODE_FIFO_KHR;
	}

	VkExtent2D vkDisplay::GetSwapExtent() {
		VkSurfaceCapabilitiesKHR capabilities;
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetNativePhysicalDevice(), surface, &capabilities);

		if (capabilities.currentExtent.width != std::numeric_limits<uint32>::max()) {
			return capabilities.currentExtent;
		} else {
			Math::UInt2 size = window->GetClientSize();

			return {
				std::clamp((uint32) size.x, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
				std::clamp((uint32) size.y, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)
			};
		}
	}
}