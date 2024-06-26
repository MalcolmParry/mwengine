#pragma once

#include "src/pch.h"
#include "vulkan/vulkan.h"
#include "vkInstance.h"

namespace mwengine::RenderAPI::Vulkan::Utils {
	VkCommandBuffer BeginSingleTimeCommands(vkInstance* instance);
	void EndSingleTimeCommands(vkInstance* instance, VkCommandBuffer commandBuffer);
	uint32 FindMemoryType(vkInstance* instance, uint32 typeFilter, VkMemoryPropertyFlags properties);
	void CreateBuffer(vkInstance* instance, VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkBuffer& buffer, VkDeviceMemory& bufferMemory);
	void CopyBuffer(vkInstance* instance, VkBuffer srcBuffer, VkBuffer dstBuffer, uint32 size, uint32 srcOffset, uint32 dstOffset);

	void CreateImage(vkInstance* instance, Math::UInt2& size, VkFormat format, VkImageTiling tiling, VkImageUsageFlags usage, VkMemoryPropertyFlags properties, VkImage& image, VkDeviceMemory& imageMemory);
	void TransitionImageLayout(vkInstance* instance, VkImage image, VkFormat format, VkImageLayout oldLayout, VkImageLayout newLayout);
	void CopyBufferToImage(vkInstance* instance, VkBuffer buffer, VkImage image, Math::UInt2& size);
	VkImageView CreateImageView(vkInstance* instance, VkImage image, VkFormat format, VkImageAspectFlags aspectFlags);
	VkFormat GetDepthFormat(vkInstance* instance);
}