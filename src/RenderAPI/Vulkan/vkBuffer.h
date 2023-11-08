#pragma once

#include "vkInstance.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkBuffer {
	public:
		vkBuffer(vkInstance* instance, uint32 size);
		~vkBuffer();

		void SetData(uint32 size, uint32 srcOffset, uint32 dstOffset, void* data);

		uint32 GetSize();
		VkBuffer GetNativeBuffer();
		VkDeviceMemory GetNativeDeviceMemory();
	private:
		static VkCommandBuffer BeginSingleTimeCommands(vkInstance* instance);
		static void EndSingleTimeCommands(vkInstance* instance, VkCommandBuffer commandBuffer);
		static uint32 FindMemoryType(vkInstance* instance, uint32 typeFilter, VkMemoryPropertyFlags properties);
		static void CreateBuffer(vkInstance* instance, VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkBuffer& buffer, VkDeviceMemory& bufferMemory);
		static void CopyBuffer(vkInstance* instance, VkBuffer srcBuffer, VkBuffer dstBuffer, uint32 size, uint32 srcOffset, uint32 dstOffset);

		vkInstance* instance;
		VkBuffer buffer;
		VkDeviceMemory deviceMemory;
		uint32 size;

		friend class vkImage;
	};
}