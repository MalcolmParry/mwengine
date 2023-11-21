#pragma once

#include "vkInstance.h"

namespace mwengine::RenderAPI::Vulkan {
	enum BufferUsage : uint8 {
		BUFFER_USAGE_VERTEX = MW_BIT(0),
		BUFFER_USAGE_INDEX = MW_BIT(1),
		BUFFER_USAGE_INSTANCE = BUFFER_USAGE_VERTEX,
		BUFFER_USAGE_UNIFORM = MW_BIT(2),
		BUFFER_USAGE_ALL = 0xFF
	};

	class vkBuffer {
	public:
		vkBuffer(vkInstance* instance, uint32 size, BufferUsage usage = BUFFER_USAGE_ALL);
		~vkBuffer();

		void SetData(void* data, uint32 size, uint32 offset = 0);
		void SetData(std::vector<uint8>& data, uint32 offset = 0);
		std::vector<uint8>& GetData(uint32 size, uint32 offset = 0);

		uint32 GetSize();
		VkBuffer GetNativeBuffer();
		VkDeviceMemory GetNativeDeviceMemory();
	private:
		vkInstance* instance;
		VkBuffer buffer;
		VkDeviceMemory deviceMemory;
		uint32 size;
	};

	struct BufferRegion {
		BufferRegion(vkBuffer* buffer = nullptr, uint32 size = 0, uint32 offset = 0);

		vkBuffer* buffer;
		uint32 size;
		uint32 offset;

		void SetData(void* data);
		void SetData(std::vector<uint8>& data);
		std::vector<uint8>& GetData();
	};
}