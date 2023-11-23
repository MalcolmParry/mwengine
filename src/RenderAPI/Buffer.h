#pragma once

#include "Instance.h"

namespace mwengine::RenderAPI {
	enum BufferUsage : uint8 {
		BUFFER_USAGE_VERTEX = MW_BIT(0),
		BUFFER_USAGE_INDEX = MW_BIT(1),
		BUFFER_USAGE_INSTANCE = BUFFER_USAGE_VERTEX,
		BUFFER_USAGE_UNIFORM = MW_BIT(2),
		BUFFER_USAGE_ALL = 0xFF
	};

	class Buffer {
	public:
		static Buffer* Create(Instance* instance, uint32 size, BufferUsage usage = BUFFER_USAGE_ALL);
		virtual ~Buffer() {};

		virtual void SetData(void* data, uint32 size, uint32 offset = 0) = 0;
		virtual void SetData(std::vector<uint8>& data, uint32 offset = 0) = 0;
		virtual std::vector<uint8>& GetData(uint32 size, uint32 offset = 0) = 0;
		virtual uint32 GetSize() = 0;
	};

	struct BufferRegion {
		BufferRegion(Buffer* buffer = nullptr, uint32 size = 0, uint32 offset = 0);

		Buffer* buffer;
		uint32 size;
		uint32 offset;

		void SetData(void* data);
		void SetData(std::vector<uint8>& data);
		std::vector<uint8>& GetData();
	};
}