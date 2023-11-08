#include "pch.h"
#include "vkBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	vkBuffer::vkBuffer(vkInstance* instance, uint32 size) {
		this->instance = instance;
		this->size = size;

		CreateBuffer(instance, size, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, buffer, deviceMemory);
	}

	vkBuffer::~vkBuffer() {
		vkDestroyBuffer(instance->GetNativeDevice(), buffer, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), deviceMemory, nullptr);
	}

	void vkBuffer::SetData(uint32 size, uint32 srcOffset, uint32 dstOffset, void* data) {
		VkBuffer stagingBuffer;
		VkDeviceMemory stagingMemory;

		CreateBuffer(instance, size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, stagingBuffer, stagingMemory);

		void* map;
		vkMapMemory(instance->GetNativeDevice(), stagingMemory, 0, size, 0, &map);
		memcpy(map, data, size);
		vkUnmapMemory(instance->GetNativeDevice(), stagingMemory);

		CopyBuffer(instance, stagingBuffer, buffer, size, srcOffset, dstOffset);

		vkDestroyBuffer(instance->GetNativeDevice(), stagingBuffer, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), stagingMemory, nullptr);
	}

	uint32 vkBuffer::GetSize() {
		return size;
	}

	VkBuffer vkBuffer::GetNativeBuffer() {
		return buffer;
	}

	VkDeviceMemory vkBuffer::GetNativeDeviceMemory() {
		return deviceMemory;
	}

	VkCommandBuffer vkBuffer::BeginSingleTimeCommands(vkInstance* instance) {
		VkQueue graphicsQueue;
		vkGetDeviceQueue(instance->GetNativeDevice(), instance->GetPhysicalDevice()->GetGraphicsQueueFamily().value(), 0, &graphicsQueue);

		VkCommandBufferAllocateInfo allocInfo {};
		allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
		allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		allocInfo.commandPool = instance->GetNativeCommandPool();
		allocInfo.commandBufferCount = 1;

		VkCommandBuffer commandBuffer;
		vkAllocateCommandBuffers(instance->GetNativeDevice(), &allocInfo, &commandBuffer);

		VkCommandBufferBeginInfo beginInfo {};
		beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
		beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

		vkBeginCommandBuffer(commandBuffer, &beginInfo);

		return commandBuffer;
	}

	void vkBuffer::EndSingleTimeCommands(vkInstance* instance, VkCommandBuffer commandBuffer) {
		VkQueue graphicsQueue;
		vkGetDeviceQueue(instance->GetNativeDevice(), instance->GetPhysicalDevice()->GetGraphicsQueueFamily().value(), 0, &graphicsQueue);

		vkEndCommandBuffer(commandBuffer);

		VkSubmitInfo submitInfo {};
		submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
		submitInfo.commandBufferCount = 1;
		submitInfo.pCommandBuffers = &commandBuffer;

		vkQueueSubmit(graphicsQueue, 1, &submitInfo, VK_NULL_HANDLE);
		vkQueueWaitIdle(graphicsQueue);

		vkFreeCommandBuffers(instance->GetNativeDevice(), instance->GetNativeCommandPool(), 1, &commandBuffer);
	}

	uint32 vkBuffer::FindMemoryType(vkInstance* instance, uint32 typeFilter, VkMemoryPropertyFlags properties) {
		VkPhysicalDeviceMemoryProperties memProperties;
		vkGetPhysicalDeviceMemoryProperties(instance->GetPhysicalDevice()->GetNativePhysicalDevice(), &memProperties);

		for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
			if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
				return i;
			}
		}

		MW_ERROR("Failed to find suitible memory type.");
		return 0;
	}

	void vkBuffer::CreateBuffer(vkInstance* instance, VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkBuffer& buffer, VkDeviceMemory& bufferMemory) {
		VkBufferCreateInfo bufferInfo {};
		bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
		bufferInfo.size = size;
		bufferInfo.usage = usage;
		bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

		if (vkCreateBuffer(instance->GetNativeDevice(), &bufferInfo, nullptr, &buffer) != VK_SUCCESS) {
			MW_ERROR("Failed to create buffer.");
		}

		VkMemoryRequirements memRequirements;
		vkGetBufferMemoryRequirements(instance->GetNativeDevice(), buffer, &memRequirements);

		VkMemoryAllocateInfo allocInfo {};
		allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
		allocInfo.allocationSize = memRequirements.size;
		allocInfo.memoryTypeIndex = FindMemoryType(instance, memRequirements.memoryTypeBits, properties);

		if (vkAllocateMemory(instance->GetNativeDevice(), &allocInfo, nullptr, &bufferMemory) != VK_SUCCESS) {
			MW_ERROR("Failed to allocate buffer memory.");
		}

		vkBindBufferMemory(instance->GetNativeDevice(), buffer, bufferMemory, 0);
	}

	void vkBuffer::CopyBuffer(vkInstance* instance, VkBuffer srcBuffer, VkBuffer dstBuffer, uint32 size, uint32 srcOffset, uint32 dstOffset) {
		VkCommandBuffer commandBuffer = BeginSingleTimeCommands(instance);

		VkBufferCopy copyRegion {};
		copyRegion.srcOffset = srcOffset;
		copyRegion.dstOffset = dstOffset;
		copyRegion.size = size;
		vkCmdCopyBuffer(commandBuffer, srcBuffer, dstBuffer, 1, &copyRegion);

		EndSingleTimeCommands(instance, commandBuffer);
	}
}