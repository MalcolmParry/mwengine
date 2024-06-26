#include "pch.h"
#include "vkImage.h"
#include "vkUtils.h"

namespace mwengine::RenderAPI::Vulkan {
	vkImage::vkImage(Instance* instance, Math::UInt2 size) {
		this->instance = (vkInstance*) instance;
		resolution = size;
		this->size = size.x * size.y * 4;
		layout = VK_IMAGE_LAYOUT_UNDEFINED;

		Utils::CreateImage(
			(vkInstance*) instance,
			size,
			VK_FORMAT_R8G8B8A8_SRGB,
			VK_IMAGE_TILING_OPTIMAL,
			VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
			VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
			image,
			deviceMemory
		);

		VkImageViewCreateInfo viewInfo {};
		viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
		viewInfo.image = image;
		viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
		viewInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
		viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
		viewInfo.subresourceRange.baseMipLevel = 0;
		viewInfo.subresourceRange.levelCount = 1;
		viewInfo.subresourceRange.baseArrayLayer = 0;
		viewInfo.subresourceRange.layerCount = 1;

		if (vkCreateImageView(((vkInstance*) instance)->GetNativeDevice(), &viewInfo, nullptr, &imageView) != VK_SUCCESS) {
			MW_ERROR("Failed to create texture image view.");
		}
	}

	vkImage::~vkImage() {
		vkDestroyImageView(instance->GetNativeDevice(), imageView, nullptr);
		vkDestroyImage(instance->GetNativeDevice(), image, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), deviceMemory, nullptr);
	}

	void vkImage::SetData(void* data) {
		VkBuffer stagingBuffer;
		VkDeviceMemory stagingMemory;

		Utils::CreateBuffer(instance, size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, stagingBuffer, stagingMemory);

		void* map;
		vkMapMemory(instance->GetNativeDevice(), stagingMemory, 0, size, 0, &map);
		memcpy(map, data, size);
		vkUnmapMemory(instance->GetNativeDevice(), stagingMemory);

		Utils::TransitionImageLayout(instance, image, VK_FORMAT_R8G8B8A8_SRGB, layout, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
		Utils::CopyBufferToImage(instance, stagingBuffer, image, resolution);
		Utils::TransitionImageLayout(instance, image, VK_FORMAT_R8G8B8A8_SRGB, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
		layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

		vkDestroyBuffer(instance->GetNativeDevice(), stagingBuffer, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), stagingMemory, nullptr);
	}

	Instance* vkImage::GetInstance() {
		return (Instance*) instance;
	}

	VkImage vkImage::GetNativeImage() {
		return image;
	}

	VkDeviceMemory vkImage::GetNativeDeviceMemory() {
		return deviceMemory;
	}

	VkImageView vkImage::GetNativeImageView() {
		return imageView;
	}

	uint32 vkImage::GetSize() {
		return size;
	}

	Math::UInt2 vkImage::GetResolution() {
		return resolution;
	}

	vkTexture::vkTexture(Instance* instance, Image* image, bool pixelated) {
		this->instance = (vkInstance*) instance;
		this->image = (vkImage*) image;

		VkFilter filter = VK_FILTER_LINEAR;
		if (pixelated)
			filter = VK_FILTER_NEAREST;

		VkPhysicalDeviceProperties properties {};
		vkGetPhysicalDeviceProperties(((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetNativePhysicalDevice(), &properties);

		VkSamplerCreateInfo samplerInfo {};
		samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
		samplerInfo.magFilter = filter;
		samplerInfo.minFilter = filter;
		samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT;
		samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT;
		samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
		samplerInfo.anisotropyEnable = VK_TRUE;
		samplerInfo.maxAnisotropy = properties.limits.maxSamplerAnisotropy;
		samplerInfo.borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK;
		samplerInfo.unnormalizedCoordinates = VK_FALSE;
		samplerInfo.compareEnable = VK_FALSE;
		samplerInfo.compareOp = VK_COMPARE_OP_ALWAYS;
		samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
		samplerInfo.mipLodBias = 0.0f;
		samplerInfo.minLod = 0.0f;
		samplerInfo.maxLod = 0.0f;

		if (vkCreateSampler(this->instance->GetNativeDevice(), &samplerInfo, nullptr, &sampler) != VK_SUCCESS) {
			MW_ERROR("Failed to create texture sampler.");
		}
	}

	vkTexture::~vkTexture() {
		vkDestroySampler(instance->GetNativeDevice(), sampler, nullptr);
	}

	Instance* vkTexture::GetInstance() {
		return image->GetInstance();
	}

	Image* vkTexture::GetImage() {
		return (Image*) image;
	}

	VkSampler vkTexture::GetNativeSampler() {
		return sampler;
	}
}