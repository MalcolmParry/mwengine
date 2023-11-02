#include "pch.h"
#include "vkCommandBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	vkCommandBuffer::vkCommandBuffer(vkDisplay* display) {
		this->display = display;
		this->frameBuffer = nullptr;
		this->renderFinishedSemaphore = nullptr;
		this->inFlightFence = nullptr;

		VkCommandPoolCreateInfo poolInfo {};
		poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
		poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
		poolInfo.queueFamilyIndex = display->GetPhysicalDevice()->GetGraphicsQueueFamily().value();

		if (vkCreateCommandPool(display->GetNativeDevice(), &poolInfo, nullptr, &commandPool) != VK_SUCCESS) {
			MW_ERROR("Failed to create command pool.");
		}

		VkCommandBufferAllocateInfo allocInfo {};
		allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
		allocInfo.commandPool = commandPool;
		allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		allocInfo.commandBufferCount = 1;

		if (vkAllocateCommandBuffers(display->GetNativeDevice(), &allocInfo, &commandBuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to allocate command buffer.");
		}

		// fence and semaphore

		VkSemaphoreCreateInfo semaphoreInfo {};
		semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

		VkFenceCreateInfo fenceInfo {};
		fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
		fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

		if (vkCreateSemaphore(display->GetNativeDevice(), &semaphoreInfo, nullptr, &renderFinishedSemaphore) != VK_SUCCESS ||
			vkCreateFence(display->GetNativeDevice(), &fenceInfo, nullptr, &inFlightFence) != VK_SUCCESS) {
			MW_ERROR("Failed to create semaphores.");
		}
	}

	vkCommandBuffer::~vkCommandBuffer() {
		vkDeviceWaitIdle(display->GetNativeDevice());

		vkDestroySemaphore(display->GetNativeDevice(), renderFinishedSemaphore, nullptr);
		vkDestroyFence(display->GetNativeDevice(), inFlightFence, nullptr);
		vkDestroyCommandPool(display->GetNativeDevice(), commandPool, nullptr);
	}

	void vkCommandBuffer::StartFrame(vkFrameBuffer* frameBuffer) {
		vkWaitForFences(display->GetNativeDevice(), 1, &inFlightFence, VK_TRUE, UINT64_MAX);
		vkResetFences(display->GetNativeDevice(), 1, &inFlightFence);
		vkResetCommandBuffer(commandBuffer, 0);

		this->frameBuffer = frameBuffer;

		VkCommandBufferBeginInfo beginInfo {};
		beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
		beginInfo.flags = 0;
		beginInfo.pInheritanceInfo = nullptr;

		if (vkBeginCommandBuffer(commandBuffer, &beginInfo) != VK_SUCCESS) {
			MW_ERROR("Failed to begin recording command buffer.");
		}

		VkRenderPassBeginInfo renderPassInfo {};
		renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
		renderPassInfo.renderPass = display->GetNativeRenderPass();
		renderPassInfo.framebuffer = frameBuffer->GetNativeFrameBuffer();
		renderPassInfo.renderArea.offset = { 0, 0 };
		renderPassInfo.renderArea.extent = display->GetExtent2D();

		VkClearValue clearColor = { { { 0.0f, 0.0f, 0.0f, 1.0f } } };
		renderPassInfo.clearValueCount = 1;
		renderPassInfo.pClearValues = &clearColor;

		vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
	}

	void vkCommandBuffer::EndFrame() {
		vkCmdEndRenderPass(commandBuffer);

		if (vkEndCommandBuffer(commandBuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to record command buffer.");
		}

		VkSubmitInfo submitInfo {};
		submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;

		VkPipelineStageFlags waitStages[] = { VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT };
		submitInfo.waitSemaphoreCount = 0;
		submitInfo.pWaitSemaphores = nullptr;
		submitInfo.pWaitDstStageMask = waitStages;
		submitInfo.commandBufferCount = 1;
		submitInfo.pCommandBuffers = &commandBuffer;

		VkSemaphore signalSemaphores[] = { renderFinishedSemaphore };
		submitInfo.signalSemaphoreCount = 1;
		submitInfo.pSignalSemaphores = signalSemaphores;

		VkQueue graphicsQueue;
		vkGetDeviceQueue(display->GetNativeDevice(), display->GetPhysicalDevice()->GetGraphicsQueueFamily().value(), 0, &graphicsQueue);

		if (vkQueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFence) != VK_SUCCESS) {
			MW_ERROR("Failed to submit draw command buffer.");
		}
	}

	void vkCommandBuffer::PresentFrame(vkDisplay* display) {
		VkSemaphore signalSemaphores[] = { renderFinishedSemaphore };
		VkSwapchainKHR swapChains[] = { display->GetNativeSwapchain() };
		uint32 imageIndex = frameBuffer->GetSwapchainImageIndex();

		VkPresentInfoKHR presentInfo {};
		presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
		presentInfo.waitSemaphoreCount = 1;
		presentInfo.pWaitSemaphores = signalSemaphores;
		presentInfo.swapchainCount = 1;
		presentInfo.pSwapchains = swapChains;
		presentInfo.pImageIndices = &imageIndex;
		presentInfo.pResults = nullptr;

		VkQueue presentQueue;
		vkGetDeviceQueue(display->GetNativeDevice(), display->GetPhysicalDevice()->GetPresentQueueFamily().value(), 0, &presentQueue);

		vkQueuePresentKHR(presentQueue, &presentInfo);
	}

	void vkCommandBuffer::QueueDraw(vkGraphicsPipeline* graphicsPipeline) {
		VkExtent2D extent = display->GetExtent2D();

		vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline->GetNativePipeline());

		VkViewport viewport {};
		viewport.x = 0.0f;
		viewport.y = 0.0f;
		viewport.width = (float) extent.width;
		viewport.height = (float) extent.height;
		viewport.minDepth = 0.0f;
		viewport.maxDepth = 1.0f;
		vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

		VkRect2D scissor {};
		scissor.offset = { 0, 0 };
		scissor.extent = extent;
		vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

		vkCmdDraw(commandBuffer, graphicsPipeline->GetVertexCount(), 1, 0, 0);
	}
}