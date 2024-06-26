#include "pch.h"
#include "vkCommandBuffer.h"

namespace mwengine::RenderAPI::Vulkan {
	vkCommandBuffer::vkCommandBuffer(Instance* instance) {
		this->instance = (vkInstance*) instance;
		this->framebuffer = nullptr;

		VkCommandBufferAllocateInfo allocInfo {};
		allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
		allocInfo.commandPool = this->instance->GetNativeCommandPool();
		allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
		allocInfo.commandBufferCount = 1;

		if (vkAllocateCommandBuffers(this->instance->GetNativeDevice(), &allocInfo, &commandBuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to allocate command buffer.");
		}
	}

	vkCommandBuffer::~vkCommandBuffer() {
		vkDeviceWaitIdle(instance->GetNativeDevice());
		vkFreeCommandBuffers(instance->GetNativeDevice(), instance->GetNativeCommandPool(), 1, &commandBuffer);
	}

	void vkCommandBuffer::StartFrame(RenderPass* renderPass, Framebuffer* framebuffer) {
		this->framebuffer = (vkFramebuffer*) framebuffer;

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
		renderPassInfo.renderPass = ((vkRenderPass*) renderPass)->GetNativeRenderPass();
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

	void vkCommandBuffer::EndFrame(Semaphore* waitSemaphore, Semaphore* signalSemaphore, Fence* signalFence) {
		vkCmdEndRenderPass(commandBuffer);

		if (vkEndCommandBuffer(commandBuffer) != VK_SUCCESS) {
			MW_ERROR("Failed to record command buffer.");
		}

		VkSemaphore nativeWaitSemaphore = nullptr;
		if (waitSemaphore != nullptr)
			nativeWaitSemaphore = ((vkSemaphore*) waitSemaphore)->GetNativeSemaphore();

		VkSemaphore nativeSignalSemaphore = nullptr;
		if (signalSemaphore != nullptr)
			nativeSignalSemaphore = ((vkSemaphore*) signalSemaphore)->GetNativeSemaphore();

		VkFence nativeSignalFence = nullptr;
		if (signalFence != nullptr)
			nativeSignalFence = ((vkFence*) signalFence)->GetNativeFence();

		VkSubmitInfo submitInfo {};
		submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;

		VkPipelineStageFlags waitStages[] = { VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT };
		submitInfo.waitSemaphoreCount = (nativeWaitSemaphore != nullptr) ? 1 : 0;
		submitInfo.pWaitSemaphores = &nativeWaitSemaphore;
		submitInfo.pWaitDstStageMask = waitStages;
		submitInfo.commandBufferCount = 1;
		submitInfo.pCommandBuffers = &commandBuffer;

		submitInfo.signalSemaphoreCount = 1;
		submitInfo.pSignalSemaphores = &nativeSignalSemaphore;

		VkQueue graphicsQueue;
		vkGetDeviceQueue(instance->GetNativeDevice(), ((vkPhysicalDevice*) instance->GetPhysicalDevice())->GetGraphicsQueueFamily().value(), 0, &graphicsQueue);

		if (vkQueueSubmit(graphicsQueue, 1, &submitInfo, nativeSignalFence) != VK_SUCCESS) {
			MW_ERROR("Failed to submit draw command buffer.");
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