#pragma once

#include "src/pch.h"
#include "vkDisplay.h"
#include "vkGraphicsPipeline.h"
#include "../CommandBuffer.h"
#include "vkFramebuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkCommandBuffer : CommandBuffer {
	public:
		vkCommandBuffer(Instance* instance);
		virtual ~vkCommandBuffer();

		virtual void StartFrame(RenderPass* renderPass, Framebuffer* framebuffer);
		virtual void EndFrame(Semaphore* waitSemaphore, Semaphore* signalSemaphore, Fence* signalFence);

		virtual void QueueDraw(
			GraphicsPipeline* graphicsPipeline,
			BufferRegion vertexBuffer = {},
			BufferRegion indexBuffer = {},
			BufferRegion instanceBuffer = {},
			ResourceSet* resourceSet = nullptr
		);
	private:
		vkInstance* instance;
		VkCommandBuffer commandBuffer;

		// Set in StartFrame()
		vkFramebuffer* framebuffer;
	};
}