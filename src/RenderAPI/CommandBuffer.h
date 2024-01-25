#pragma once

#include "src/pch.h"
#include "Display.h"
#include "GraphicsPipeline.h"

namespace mwengine::RenderAPI {
	class CommandBuffer {
	public:
		static CommandBuffer* Create(Instance* instance);
		virtual ~CommandBuffer() {};

		virtual void StartFrame(Framebuffer* framebuffer) = 0;
		virtual void EndFrame() = 0;

		virtual void QueueDraw(
			GraphicsPipeline* graphicsPipeline,
			BufferRegion vertexBuffer = {},
			BufferRegion indexBuffer = {},
			BufferRegion instanceBuffer = {},
			ResourceSet* resourceSet = nullptr
		) = 0;
	};
}