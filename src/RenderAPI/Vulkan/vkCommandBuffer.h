#pragma once

#include "src/pch.h"
#include "vkDisplay.h"
#include "vkGraphicsPipeline.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkCommandBuffer {
	public:
		vkCommandBuffer(vkInstance* instance);
		~vkCommandBuffer();

		void StartFrame(vkFrameBuffer* frameBuffer);
		void EndFrame();
		void PresentFrame(vkDisplay* display);

		void QueueDraw(vkGraphicsPipeline* graphicsPipeline);
	private:
		vkInstance* instance;
		VkCommandPool commandPool;
		VkCommandBuffer commandBuffer;

		vkFrameBuffer* frameBuffer;
		VkSemaphore renderFinishedSemaphore;
		VkFence inFlightFence;
	};
}