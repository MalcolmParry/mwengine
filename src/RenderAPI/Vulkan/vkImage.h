#pragma once

#include "src/pch.h"
#include "vkInstance.h"
#include "vkBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkImage {
	public:
		vkImage(vkInstance* instance, glm::uvec2 size);
		~vkImage();

		void SetData(glm::uvec2 size, void* data);

		VkImage GetNativeImage();
		VkDeviceMemory GetNativeDeviceMemory();
		VkImageView GetNativeImageView();
		uint32 GetSize();
		glm::uvec2 GetResolution();
	private:
		void TransitionImageLayout(VkFormat format, VkImageLayout oldLayout, VkImageLayout newLayout);
		void CopyBufferToImage(VkBuffer buffer, VkImage image, glm::uvec2 size);

		vkInstance* instance;
		VkImage image;
		VkDeviceMemory deviceMemory;
		VkImageView imageView;
		uint32 size;
		glm::uvec2 resolution;
		VkImageLayout layout;
	};

	class vkTexture {
	public:
		vkTexture(vkInstance* instance, vkImage* image, bool pixelated = false);
		~vkTexture();

		vkImage* GetImage();
		VkSampler GetNativeSampler();
	private:
		vkInstance* instance;
		vkImage* image;
		VkSampler sampler;
	};
}