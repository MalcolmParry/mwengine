#include "pch.h"
#include "vkCommandBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	vkCommandBuffer::vkCommandBuffer(Instance* instance) {
		this->instance = (vkInstance*) instance;
		this->renderFinishedSemaphore = nullptr;
		this->inFlightFence = nullptr;
		this->framebuffer = nullptr;

		VkCommandBufferAllocateInfo allocInfo {};
		allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
		allocInfo.commandPool = this->instance->GetNativeCommandPool();
		allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		allocInfo.commandBufferCount = 1;

		if (vkAllocateCommandBuffers(this->instance->GetNativeDevice(), &allocInfo, &commandBuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to allocate command buffer.");
		}

		// fence and semaphore

		VkSemaphoreCreateInfo semaphoreInfo {};
		semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

		VkFenceCreateInfo fenceInfo {};
		fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
		fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

		if (vkCreateSemaphore(this->instance->GetNativeDevice(), &semaphoreInfo, nullptr, &renderFinishedSemaphore) != VK_SUCCESS ||
			vkCreateFence(this->instance->GetNativeDevice(), &fenceInfo, nullptr, &inFlightFence) != VK_SUCCESS) {
			MW_ERROR("Failed to create semaphores.");
		}
	}

	vkCommandBuffer::~vkCommandBuffer() {
		vkDeviceWaitIdle(instance->GetNativeDevice());

		vkDestroySemaphore(instance->GetNativeDevice(), renderFinishedSemaphore, nullptr);
		vkDestroyFence(instance->GetNativeDevice(), inFlightFence, nullptr);
		vkFreeCommandBuffers(instance->GetNativeDevice(), instance->GetNativeCommandPool(), 1, &commandBuffer);
	}

	void vkCommandBuffer::StartFrame(Framebuffer* framebuffer) {
		this->framebuffer = (vkFramebuffer*) framebuffer;

		((vkFramebuffer*) framebuffer)->NativeAdvance();

		vkWaitForFences(instance->GetNativeDevice(), 1, &inFlightFence, VK_TRUE, UINT64_MAX);
		vkResetFences(instance->GetNativeDevice(), 1, &inFlightFence);
		vkResetCommandBuffer(commandBuffer, 0);

		VkCommandBufferBeginInfo beginInfo {};
		beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
		beginInfo.flags = 0;
		beginInfo.pInheritanceInfo = nullptr;

		if (vkBeginCommandBuffer(commandBuffer, &beginInfo) != VK_SUCCESS) {
			MW_ERROR("Failed to begin recording command buffer.");
		}

		Math::UInt2 size = framebuffer->GetSize();

		VkRenderPassBeginInfo renderPassInfo {};
		renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
		renderPassInfo.renderPass = ((vkFramebuffer*) framebuffer)->GetNativeRenderPass();
		renderPassInfo.framebuffer = ((vkFramebuffer*) framebuffer)->GetNativeFramebuffer();
		renderPassInfo.renderArea.offset = { 0, 0 };
		renderPassInfo.renderArea.extent = { size.x, size.y };

		VkClearValue clearValues[2] {};
		clearValues[0].color = { { 0.0f, 0.0f, 0.0f, 1.0f } };
		clearValues[1].depthStencil = { 1.0f, 0 };

		renderPassInfo.clearValueCount = 2;
		renderPassInfo.pClearValues = clearValues;

		vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
	}

	void vkCommandBuffer::EndFrame() {
		vkCmdEndRenderPass(commandBuffer);

		if (vkEndCommandBuffer(commandBuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to record command buffer.");
		}

		VkSemaphore semaphore = nullptr;
		if (framebuffer->IsFromDisplay()) {
			semaphore = ((vkFramebuffer*) framebuffer)->GetNativeSemaphore();
		}

		VkSubmitInfo submitInfo {};
		submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;

		VkPipelineStageFlags waitStages[] = { VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT };
		submitInfo.waitSemaphoreCount = 1;
		submitInfo.pWaitSemaphores = &semaphore;
		submitInfo.pWaitDstStageMask = waitStages;
		submitInfo.commandBufferCount = 1;
		submitInfo.pCommandBuffers = &commandBuffer;

		VkSemaphore signalSemaphores[] = { renderFinishedSemaphore };
		submitInfo.signalSemaphoreCount = 1;
		submitInfo.pSignalSemaphores = signalSemaphores;

		VkQueue graphicsQueue;
		vkGetDeviceQueue(instance->GetNativeDevice(), ((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetGraphicsQueueFamily().value(), 0, &graphicsQueue);

		if (vkQueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFence) != VK_SUCCESS) {
			MW_ERROR("Failed to submit draw command buffer.");
		}

		if (framebuffer->IsFromDisplay()) {
			uint32 imageIndex = ((vkFramebuffer*) framebuffer)->GetNativeImageIndex();

			VkSwapchainKHR swapchains[] = { framebuffer->GetNativeSwapchain() };

			VkPresentInfoKHR presentInfo {};
			presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
			presentInfo.waitSemaphoreCount = 1;
			presentInfo.pWaitSemaphores = &renderFinishedSemaphore;
			presentInfo.swapchainCount = 1;
			presentInfo.pSwapchains = swapchains;
			presentInfo.pImageIndices = &imageIndex;
			presentInfo.pResults = nullptr;

			VkQueue presentQueue;
			vkGetDeviceQueue(instance->GetNativeDevice(), ((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetPresentQueueFamily().value(), 0, &presentQueue);

			vkQueuePresentKHR(presentQueue, &presentInfo);
		}

		this->framebuffer = nullptr;
	}

	void vkCommandBuffer::QueueDraw(
		GraphicsPipeline* graphicsPipeline,
		BufferRegion vertexBuffer,
		BufferRegion indexBuffer,
		BufferRegion instanceBuffer,
		ResourceSet* resourceSet
	) {
		Math::UInt2 size = framebuffer->GetSize();

		vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, ((vkGraphicsPipeline*) graphicsPipeline)->GetNativePipeline());

		if (resourceSet != nullptr) {
			VkDescriptorSet descriptorSet = ((vkResourceSet*) resourceSet)->GetNativeDescriptorSet();

			vkCmdBindDescriptorSets(
				commandBuffer,
				VK_PIPELINE_BIND_POINT_GRAPHICS,
				((vkGraphicsPipeline*) graphicsPipeline)->GetNativePipelineLayout(),
				0,
				1,
				&descriptorSet,
				0,
				nullptr
			);
		}

		VkBuffer vertexBuffers[2];
		VkDeviceSize offsets[2];
		uint32 i = 0;
		if (vertexBuffer.buffer != nullptr) {
			vertexBuffers[i] = ((vkBuffer*) vertexBuffer.buffer)->GetNativeBuffer();
			offsets[i] = vertexBuffer.offset;
			i++;
		}

		if (instanceBuffer.buffer != nullptr) {
			vertexBuffers[i] = ((vkBuffer*) instanceBuffer.buffer)->GetNativeBuffer();
			offsets[i] = instanceBuffer.offset;
			i++;
		}

		if (i != 0) {
			vkCmdBindVertexBuffers(commandBuffer, 0, i, vertexBuffers, offsets);
		}

		if (indexBuffer.buffer != nullptr) {
			vkCmdBindIndexBuffer(commandBuffer, ((vkBuffer*) indexBuffer.buffer)->GetNativeBuffer(), indexBuffer.offset, VK_INDEX_TYPE_UINT16);
		}

		VkViewport viewport {};
		viewport.x = 0.0f;
		viewport.y = 0.0f;
		viewport.width = (float) size.x;
		viewport.height = (float) size.y;
		viewport.minDepth = 0.0f;
		viewport.maxDepth = 1.0f;
		vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

		VkRect2D scissor {};
		scissor.offset = { 0, 0 };
		scissor.extent = { size.x, size.y };
		vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

		vkCmdDrawIndexed(commandBuffer, graphicsPipeline->indexCount, graphicsPipeline->instanceCount, 0, 0, 0);
	}
}