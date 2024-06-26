#include "pch.h"
#include "vkFramebuffer.h"
#include "vkDisplay.h"
#include "vkUtils.h"

namespace mwengine::RenderAPI::Vulkan {
    vkFramebuffer::vkFramebuffer(Instance* instance, RenderPass* renderPass, Image* image, Image* depthImage) {
		Create(instance, image->GetResolution(), ((vkImage*) image)->GetNativeImageView(), ((vkImage*) depthImage)->GetNativeImageView(), renderPass);
    }

    vkFramebuffer::vkFramebuffer(Instance* instance, Math::UInt2 imageResolution, VkImageView image, VkImageView depthImage, RenderPass* renderPass) {
		Create(instance, imageResolution, image, depthImage, renderPass);
	}

	vkFramebuffer::~vkFramebuffer() {
		vkDestroyFramebuffer(instance->GetNativeDevice(), framebuffer, nullptr);
	}

	Instance* vkFramebuffer::GetInstance() {
		return (Instance*) instance;
	}

	Math::UInt2 vkFramebuffer::GetSize() {
		return size;
	}

	VkFramebuffer vkFramebuffer::GetNativeFramebuffer() {
		return framebuffer;
	}

	void vkFramebuffer::Create(Instance* instance, Math::Int2 imageResolution, VkImageView image, VkImageView depthImage, RenderPass* renderPass) {
		size = imageResolution;
		this->instance = (vkInstance*) instance;

		VkImageView attachments[] = {
			image,
			depthImage
		};

		VkFramebufferCreateInfo framebufferInfo {};
		framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
		framebufferInfo.renderPass = ((vkRenderPass*) renderPass)->GetNativeRenderPass();
		framebufferInfo.attachmentCount = (depthImage == nullptr) ? 1 : 2;
		framebufferInfo.pAttachments = attachments;
		framebufferInfo.width = GetSize().x;
		framebufferInfo.height = GetSize().y;
		framebufferInfo.layers = 1;

		if (vkCreateFramebuffer(this->instance->GetNativeDevice(), &framebufferInfo, nullptr, &framebuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to create framebuffer.");
		}
	}
}