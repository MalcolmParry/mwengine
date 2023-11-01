#include "pch.h"
#include "vkDisplay.h"

namespace mwengine::RenderAPI::Vulkan {
	const std::vector<const char*> requiredDeviceExtensions = {
		VK_KHR_SWAPCHAIN_EXTENSION_NAME
	};
	
	vkDisplay::vkDisplay(vkInstance* instance, vkPhysicalDevice* physicalDevice) {
		this->instance = instance;
		this->physicalDevice = physicalDevice;
		this->format = GetSwapSurfaceFormat().format;
		this->swapchain = nullptr;

		VkDeviceQueueCreateInfo queueCreateInfos[2];
		uint32 queueFamilies[] = { physicalDevice->GetGraphicsQueueFamily().value(), physicalDevice->GetPresentQueueFamily().value() };

		float queuePriority = 1.0f;
		for (uint32 i = 0; i < 2; i++) {
			VkDeviceQueueCreateInfo queueCreateInfo {};
			queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
			queueCreateInfo.queueFamilyIndex = queueFamilies[i];
			queueCreateInfo.queueCount = 1;
			queueCreateInfo.pQueuePriorities = &queuePriority;

			queueCreateInfos[i] = queueCreateInfo;
		}

		VkPhysicalDeviceFeatures deviceFeatures { 0 };

		VkDeviceCreateInfo createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
		createInfo.pQueueCreateInfos = queueCreateInfos;
		createInfo.queueCreateInfoCount = 1;
		createInfo.pEnabledFeatures = &deviceFeatures;
		createInfo.enabledExtensionCount = requiredDeviceExtensions.size();
		createInfo.ppEnabledExtensionNames = requiredDeviceExtensions.data();

		if (vkCreateDevice(physicalDevice->GetNativePhysicalDevice(), &createInfo, nullptr, &device) != VK_SUCCESS) {
			MW_ERROR("Renderer: Failed to create logical device.");
		}

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

		if (vkCreateRenderPass(device, &renderPassInfo, nullptr, &renderPass) != VK_SUCCESS) {
			MW_ERROR("Failed to create render pass.");
		}
	}

	vkDisplay::~vkDisplay() {
		vkDestroySwapchainKHR(device, swapchain, nullptr);
		vkDestroyRenderPass(device, renderPass, nullptr);
		vkDestroyDevice(device, nullptr);
	}

	vkInstance* vkDisplay::GetInstance() {
		return instance;
	}

	vkPhysicalDevice* vkDisplay::GetPhysicalDevice() {
		return physicalDevice;
	}

	VkDevice vkDisplay::GetNativeDevice() {
		return device;
	}

	VkRenderPass vkDisplay::GetNativeRenderPass() {
		return renderPass;
	}

	void vkDisplay::CreateSwapChain() {
		VkSurfaceCapabilitiesKHR capabilities;
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice->GetNativePhysicalDevice(), instance->GetNativeSurface(), &capabilities);

		uint32 imageCount = capabilities.minImageCount + 1;
		if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount) {
			uint32 imageCount = capabilities.maxImageCount;
		}

		VkSurfaceFormatKHR imageFormat = GetSwapSurfaceFormat();
		format = imageFormat.format;
		extent = GetSwapExtent();

		VkSwapchainCreateInfoKHR createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
		createInfo.surface = instance->GetNativeSurface();
		createInfo.minImageCount = imageCount;
		createInfo.imageFormat = imageFormat.format;
		createInfo.imageColorSpace = imageFormat.colorSpace;
		createInfo.imageExtent = extent;
		createInfo.imageArrayLayers = 1;
		createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

		uint32 queueFamilyIndices[] = { physicalDevice->GetGraphicsQueueFamily().value(), physicalDevice->GetPresentQueueFamily().value() };

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
		createInfo.oldSwapchain = swapchain;

		if (vkCreateSwapchainKHR(device, &createInfo, nullptr, &swapchain) != VK_SUCCESS) {
			MW_ERROR("Failed to create swapchain.");
		}
	}

	void vkDisplay::DestroySwapChain() {

	}

	VkSurfaceFormatKHR vkDisplay::GetSwapSurfaceFormat() {
		uint32 formatCount;
		std::vector<VkSurfaceFormatKHR> formats;
		vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice->GetNativePhysicalDevice(), instance->GetNativeSurface(), &formatCount, nullptr);

		if (formatCount != 0) {
			formats.resize(formatCount);
			vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice->GetNativePhysicalDevice(), instance->GetNativeSurface(), &formatCount, formats.data());

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
		vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice->GetNativePhysicalDevice(), instance->GetNativeSurface(), &modeCount, nullptr);

		if (modeCount != 0) {
			modes.resize(modeCount);
			vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice->GetNativePhysicalDevice(), instance->GetNativeSurface(), &modeCount, modes.data());

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
		vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice->GetNativePhysicalDevice(), instance->GetNativeSurface(), &capabilities);

		if (capabilities.currentExtent.width != std::numeric_limits<uint32>::max()) {
			return capabilities.currentExtent;
		} else {
			MWATH::Int2 size = instance->GetWindow()->GetClientSize();

			return {
				std::clamp((uint32) size.x, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
				std::clamp((uint32) size.y, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)
			};
		}
	}
}