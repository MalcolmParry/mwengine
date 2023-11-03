#include "pch.h"
#include "vkDisplay.h"
#include "vkPlatform.h"

namespace mwengine::RenderAPI::Vulkan {
	const std::vector<const char*> requiredDeviceExtensions = {
		VK_KHR_SWAPCHAIN_EXTENSION_NAME
	};
	
	vkDisplay::vkDisplay(vkInstance* instance, Window* window) {
		if (window == nullptr) {
			inheritFromInstance = true;
			surface = instance->GetNativeSurface();
			this->window = window;
		} else {
			inheritFromInstance = false;
			this->window = window;
			surface = CreateSurface(window, instance->GetNativeInstance());
		}

		this->instance = instance;
		this->format = GetSwapSurfaceFormat().format;
		this->swapchain = nullptr;

		VkAttachmentDescription colorAttachment {};
		colorAttachment.format = format;
		colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
		colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
		colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
		colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
		colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
		colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

		VkAttachmentReference colorAttachmentRef {};
		colorAttachmentRef.attachment = 0;
		colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

		VkSubpassDescription subpass {};
		subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
		subpass.colorAttachmentCount = 1;
		subpass.pColorAttachments = &colorAttachmentRef;

		VkSubpassDependency dependency {};
		dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
		dependency.dstSubpass = 0;
		dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		dependency.srcAccessMask = 0;
		dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
		dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

		VkRenderPassCreateInfo renderPassInfo {};
		renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
		renderPassInfo.attachmentCount = 1;
		renderPassInfo.pAttachments = &colorAttachment;
		renderPassInfo.subpassCount = 1;
		renderPassInfo.pSubpasses = &subpass;
		renderPassInfo.dependencyCount = 1;
		renderPassInfo.pDependencies = &dependency;

		if (vkCreateRenderPass(instance->GetNativeDevice(), &renderPassInfo, nullptr, &renderPass) != VK_SUCCESS) {
			MW_ERROR("Failed to create render pass.");
		}

		CreateSwapChain();
	}

	vkDisplay::~vkDisplay() {
		DestroySwapChain();

		vkDestroySwapchainKHR(instance->GetNativeDevice(), swapchain, nullptr);
		vkDestroyRenderPass(instance->GetNativeDevice(), renderPass, nullptr);
		vkDestroyDevice(instance->GetNativeDevice(), nullptr);
		if (!inheritFromInstance)
			vkDestroySurfaceKHR(instance->GetNativeInstance(), surface, nullptr);
	}

	void vkDisplay::Rebuild() {
		vkDeviceWaitIdle(instance->GetNativeDevice());

		DestroySwapChain();
		CreateSwapChain();
	}

	vkFrameBuffer* vkDisplay::GetFrameBuffer() {
		VkFence fence;
		VkFenceCreateInfo fenceInfo {};
		fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;

		if (vkCreateFence(instance->GetNativeDevice(), &fenceInfo, nullptr, &fence) != VK_SUCCESS) {
			MW_ERROR("Failed to create fence.");
		}

		uint32_t imageIndex;
		VkResult result = vkAcquireNextImageKHR(instance->GetNativeDevice(), swapchain, UINT64_MAX, VK_NULL_HANDLE, fence, &imageIndex);

		if (result == VK_ERROR_OUT_OF_DATE_KHR) {
			Rebuild();
			return GetFrameBuffer();
		} else if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR) {
			MW_ERROR("Failed to aquire swap chain image.");
		}

		vkWaitForFences(instance->GetNativeDevice(), 1, &fence, true, UINT64_MAX);
		vkDestroyFence(instance->GetNativeDevice(), fence, nullptr);

		return framebuffers[imageIndex];
	}

	vkInstance* vkDisplay::GetInstance() {
		return instance;
	}

	VkRenderPass vkDisplay::GetNativeRenderPass() {
		return renderPass;
	}

	VkExtent2D vkDisplay::GetExtent2D() {
		return extent;
	}

	VkSwapchainKHR vkDisplay::GetNativeSwapchain() {
		return swapchain;
	}

	void vkDisplay::CreateSwapChain() {
		VkSwapchainKHR oldSwapChain = swapchain;

		VkSurfaceCapabilitiesKHR capabilities;
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), surface, &capabilities);

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

		uint32 queueFamilyIndices[] = { instance->GetPhysicalDevice()->GetGraphicsQueueFamily().value(), instance->GetPhysicalDevice()->GetPresentQueueFamily().value() };

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

		uint32 swapImageCount;
		vkGetSwapchainImagesKHR(instance->GetNativeDevice(), swapchain, &swapImageCount, nullptr);
		images.resize(swapImageCount);
		vkGetSwapchainImagesKHR(instance->GetNativeDevice(), swapchain, &swapImageCount, images.data());

		imageViews.resize(images.size());
		for (uint32 i = 0; i < images.size(); i++) {
			VkImageViewCreateInfo createInfo {};
			createInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
			createInfo.image = images[i];
			createInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
			createInfo.format = format;
			createInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
			createInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
			createInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
			createInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
			createInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
			createInfo.subresourceRange.baseMipLevel = 0;
			createInfo.subresourceRange.levelCount = 1;
			createInfo.subresourceRange.baseArrayLayer = 0;
			createInfo.subresourceRange.layerCount = 1;

			if (vkCreateImageView(instance->GetNativeDevice(), &createInfo, nullptr, &imageViews[i]) != VK_SUCCESS) {
				MW_ERROR("Failed to create image view.");
			}
		}

		framebuffers.resize(imageViews.size());
		for (uint32 i = 0; i < imageViews.size(); i++) {
			framebuffers[i] = new vkFrameBuffer(instance->GetNativeDevice(), extent, imageViews[i], renderPass, i);
		}

		if (oldSwapChain != nullptr)
			vkDestroySwapchainKHR(instance->GetNativeDevice(), oldSwapChain, nullptr);
	}

	void vkDisplay::DestroySwapChain() {
		for (vkFrameBuffer* framebuffer : framebuffers) {
			delete framebuffer;
		}

		for (VkImageView imageView : imageViews) {
			vkDestroyImageView(instance->GetNativeDevice(), imageView, nullptr);
		}
	}

	VkSurfaceFormatKHR vkDisplay::GetSwapSurfaceFormat() {
		uint32 formatCount;
		std::vector<VkSurfaceFormatKHR> formats;
		vkGetPhysicalDeviceSurfaceFormatsKHR(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), surface, &formatCount, nullptr);

		if (formatCount != 0) {
			formats.resize(formatCount);
			vkGetPhysicalDeviceSurfaceFormatsKHR(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), surface, &formatCount, formats.data());

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
		vkGetPhysicalDeviceSurfacePresentModesKHR(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), surface, &modeCount, nullptr);

		if (modeCount != 0) {
			modes.resize(modeCount);
			vkGetPhysicalDeviceSurfacePresentModesKHR(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), surface, &modeCount, modes.data());

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
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), surface, &capabilities);

		if (capabilities.currentExtent.width != std::numeric_limits<uint32>::max()) {
			return capabilities.currentExtent;
		} else {
			MWATH::Int2 size = window->GetClientSize();

			return {
				std::clamp((uint32) size.x, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
				std::clamp((uint32) size.y, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)
			};
		}
	}
}