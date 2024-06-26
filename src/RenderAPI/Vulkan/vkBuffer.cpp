#include "pch.h"
#include "vkBuffer.h"
#include "vkUtils.h"

namespace mwengine::RenderAPI::Vulkan {
	vkBuffer::vkBuffer(Instance* instance, uint64 size, BufferUsage usage) {
		this->instance = (vkInstance*) instance;
		this->size = size;

		VkBufferUsageFlags vkUsage = VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
		if (usage & BUFFER_USAGE_VERTEX)
			vkUsage |= VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
		if (usage & BUFFER_USAGE_INDEX)
			vkUsage |= VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
		if (usage & BUFFER_USAGE_UNIFORM)
			vkUsage |= VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;

		Utils::CreateBuffer((vkInstance*) instance, size, vkUsage, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, buffer, deviceMemory);
	}

	vkBuffer::~vkBuffer() {
		vkDestroyBuffer(instance->GetNativeDevice(), buffer, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), deviceMemory, nullptr);
	}

	void vkBuffer::SetData(void* data, uint64 size, uint64 offset) {
		VkBuffer stagingBuffer;
		VkDeviceMemory stagingMemory;

		Utils::CreateBuffer(instance, size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, stagingBuffer, stagingMemory);

		void* map;
		vkMapMemory(instance->GetNativeDevice(), stagingMemory, 0, size, 0, &map);
		memcpy(map, data, size);
		vkUnmapMemory(instance->GetNativeDevice(), stagingMemory);

		Utils::CopyBuffer(instance, stagingBuffer, buffer, size, 0, offset);

		vkDestroyBuffer(instance->GetNativeDevice(), stagingBuffer, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), stagingMemory, nullptr);
	}

	void vkBuffer::SetData(std::vector<uint8>& data, uint64 offset) {
		SetData(data.data(), data.size(), offset);
	}

	std::vector<uint8> vkBuffer::GetData(uint64 size, uint64 offset) {
		std::vector<uint8> data(size);

		VkBuffer stagingBuffer;
		VkDeviceMemory stagingMemory;

		Utils::CreateBuffer(instance, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, stagingBuffer, stagingMemory);

		Utils::CopyBuffer(instance, buffer, stagingBuffer, data.size(), offset, 0);

		void* map;
		vkMapMemory(instance->GetNativeDevice(), stagingMemory, 0, data.size(), 0, &map);
		memcpy(data.data(), map, size);
		vkUnmapMemory(instance->GetNativeDevice(), stagingMemory);


		vkDestroyBuffer(instance->GetNativeDevice(), stagingBuffer, nullptr);
		vkFreeMemory(instance->GetNativeDevice(), stagingMemory, nullptr);

		return data;
	}

	uint64 vkBuffer::GetSize() {
		return size;
	}

	VkBuffer vkBuffer::GetNativeBuffer() {
		return buffer;
	}

	VkDeviceMemory vkBuffer::GetNativeDeviceMemory() {
		return deviceMemory;
	}
}