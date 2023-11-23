#pragma once

#include "vkInstance.h"
#include "../Buffer.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkBuffer : Buffer {
	public:
		vkBuffer(Instance* instance, uint32 size, BufferUsage usage = BUFFER_USAGE_ALL);
		virtual ~vkBuffer();

		virtual void SetData(void* data, uint32 size, uint32 offset = 0);
		virtual void SetData(std::vector<uint8>& data, uint32 offset = 0);
		virtual std::vector<uint8>& GetData(uint32 size, uint32 offset = 0);
		virtual uint32 GetSize();

		VkBuffer GetNativeBuffer();
		VkDeviceMemory GetNativeDeviceMemory();
	private:
		vkInstance* instance;
		VkBuffer buffer;
		VkDeviceMemory deviceMemory;
		uint32 size;
	};
}