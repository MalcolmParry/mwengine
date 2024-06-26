#pragma once

#include "src/pch.h"
#include "vkInstance.h"
#include "vkBuffer.h"
#include "../Image.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkImage : Image {
	public:
		vkImage(Instance* instance, Math::UInt2 size);
		virtual ~vkImage();

		virtual void SetData(void* data);
		virtual Instance* GetInstance();
		virtual uint32 GetSize();
		virtual Math::UInt2 GetResolution();

		VkImage GetNativeImage();
		VkDeviceMemory GetNativeDeviceMemory();
		VkImageView GetNativeImageView();
	private:
		vkInstance* instance;
		VkImage image;
		VkDeviceMemory deviceMemory;
		VkImageView imageView;
		uint32 size;
		Math::UInt2 resolution;
		VkImageLayout layout;
	};

	class vkTexture : Texture {
	public:
		vkTexture(Instance* instance, Image* image, bool pixelated = false);
		virtual ~vkTexture();

		virtual Instance* GetInstance();
		virtual Image* GetImage();

		VkSampler GetNativeSampler();
	private:
		vkInstance* instance;
		vkImage* image;
		VkSampler sampler;
	};
}