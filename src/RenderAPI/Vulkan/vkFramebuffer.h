#pragma once

#include "src/pch.h"
#include "vulkan/vulkan.h"
#include "../Framebuffer.h"
#include "vkInstance.h"
#include "vkImage.h"
#include "vkRenderPass.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkFramebuffer : Framebuffer {
	public:
		vkFramebuffer(Instance* instance, RenderPass* renderPass, Image* image, Image* depthImage = nullptr);
		vkFramebuffer(Instance* instance, Math::UInt2 imageResolution, VkImageView image, VkImageView depthImage, RenderPass* renderPass);
		virtual ~vkFramebuffer();

		virtual Instance* GetInstance();
		virtual Math::UInt2 GetSize();

		VkFramebuffer GetNativeFramebuffer();
	private:
		void Create(Instance* instance, Math::Int2 imageResolution, VkImageView image, VkImageView depthImage, RenderPass* renderPass);

		vkInstance* instance;
		VkFramebuffer framebuffer;
		Math::UInt2 size;
	};
}