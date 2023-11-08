#include "pch.h"
#include "vkImage.h"

namespace mwengine::RenderAPI::Vulkan {
	vkImage::vkImage(vkInstance* instance, glm::uvec2 size) {
		this->instance = instance;
		resolution = size;
		layout = VK_IMAGE_LAYOUT_UNDEFINED;

		VkImageCreateInfo imageInfo {};
		imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
		imageInfo.imageType = VK_IMAGE_TYPE_2D;
		imageInfo.extent.width = size.x;
		imageInfo.extent.height = size.y;
		imageInfo.extent.depth = 1;
		imageInfo.mipLevels = 1;
		imageInfo.arrayLayers = 1;
		imageInfo.format = VK_FORMAT_R8G8B8A8_SRGB;
		imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
		imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
		imageInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
		imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
		imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
		imageInfo.flags = 0;

		if (vkCreateImage(instance->GetNativeDevice(), &imageInfo, nullptr, &image) != VK_SUCCESS) {
			MW_ERROR("Failed to create image.");
		}

		VkMemoryRequirements memRequirements;
		vkGetImageMemoryRequirements(instance->GetNativeDevice(), image, &memRequirements);

		this->size = memRequirements.size;

		VkMemoryAllocateInfo allocInfo {};
		allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
		allocInfo.allocationSize = memRequirements.size;
		allocInfo.memoryTypeIndex = vkBuffer::FindMemoryType(instance, memRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

		if (vkAllocateMemory(instance->GetNativeDevice(), &allocInfo, nullptr, &deviceMemory) != VK_SUCCESS) {
			MW_ERROR("Failed to allocate image memory.");
		}

		vkBindImageMemory(instance->GetNativeDevice(), image, deviceMemory, 0);

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

		if (vkCreateImageView(instance->GetNativeDevice(), &viewInfo, nullptr, &imageView) != VK_SUCCESS) {
			MW_ERROR("Failed to create texture image view.");
		}
	}

	vkImage::~vkImage() {
		vkDestroyImageView(instance->GetNativeDevice(), imageView, nullptr);
		vkDestroyImage(instance->GetNativeDevice(), image, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), deviceMemory, nullptr);
	}

	void vkImage::SetData(glm::uvec2 size, void* data) {
		VkBuffer stagingBuffer;
		VkDeviceMemory stagingMemory;
		uint32 _size = size.x * size.y * 4;

		vkBuffer::CreateBuffer(instance, _size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, stagingBuffer, stagingMemory);

		void* map;
		vkMapMemory(instance->GetNativeDevice(), stagingMemory, 0, _size, 0, &map);
		memcpy(map, data, _size);
		vkUnmapMemory(instance->GetNativeDevice(), stagingMemory);

		TransitionImageLayout(VK_FORMAT_R8G8B8A8_SRGB, layout, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
		CopyBufferToImage(stagingBuffer, image, size);
		TransitionImageLayout(VK_FORMAT_R8G8B8A8_SRGB, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
		layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;



		vkDestroyBuffer(instance->GetNativeDevice(), stagingBuffer, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), stagingMemory, nullptr);
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

	glm::uvec2 vkImage::GetResolution() {
		return resolution;
	}

	void vkImage::TransitionImageLayout(VkFormat format, VkImageLayout oldLayout, VkImageLayout newLayout) {
		VkCommandBuffer commandBuffer = vkBuffer::BeginSingleTimeCommands(instance);

		VkImageMemoryBarrier barrier {};
		barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
		barrier.oldLayout = oldLayout;
		barrier.newLayout = newLayout;
		barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
		barrier.image = image;
		barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
		barrier.subresourceRange.baseMipLevel = 0;
		barrier.subresourceRange.levelCount = 1;
		barrier.subresourceRange.baseArrayLayer = 0;
		barrier.subresourceRange.layerCount = 1;
		barrier.srcAccessMask = 0;
		barrier.dstAccessMask = 0;

		VkPipelineStageFlags sourceStage;
		VkPipelineStageFlags destinationStage;

		if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
			barrier.srcAccessMask = 0;
			barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

			sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
			destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
		} else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
			barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
			barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

			sourceStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
			destinationStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
		} else {
			MW_ERROR("Unsupported layout transition.");
		}

		vkCmdPipelineBarrier(commandBuffer, sourceStage, destinationStage, 0, 0, nullptr, 0, nullptr, 1, &barrier);

		vkBuffer::EndSingleTimeCommands(instance, commandBuffer);
	}

	void vkImage::CopyBufferToImage(VkBuffer buffer, VkImage image, glm::uvec2 size) {
		VkCommandBuffer commandBuffer = vkBuffer::BeginSingleTimeCommands(instance);

		VkBufferImageCopy region {};
		region.bufferOffset = 0;
		region.bufferRowLength = 0;
		region.bufferImageHeight = 0;

		region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
		region.imageSubresource.mipLevel = 0;
		region.imageSubresource.baseArrayLayer = 0;
		region.imageSubresource.layerCount = 1;

		region.imageOffset = { 0, 0, 0 };
		region.imageExtent = {
			size.x,
			size.y,
			1
		};

		vkCmdCopyBufferToImage(commandBuffer, buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

		vkBuffer::EndSingleTimeCommands(instance, commandBuffer);
	}

	vkTexture::vkTexture(vkInstance* instance, vkImage* image, bool pixelated) {
		this->instance = instance;
		this->image = image;

		VkFilter filter = VK_FILTER_LINEAR;
		if (pixelated)
			filter = VK_FILTER_NEAREST;

		VkPhysicalDeviceProperties properties {};
		vkGetPhysicalDeviceProperties(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), &properties);

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

		if (vkCreateSampler(instance->GetNativeDevice(), &samplerInfo, nullptr, &sampler) != VK_SUCCESS) {
			MW_ERROR("Failed to create texture sampler.");
		}
	}

	vkTexture::~vkTexture() {
		vkDestroySampler(instance->GetNativeDevice(), sampler, nullptr);
	}

	vkImage* vkTexture::GetImage() {
		return image;
	}

	VkSampler vkTexture::GetNativeSampler() {
		return sampler;
	}
}