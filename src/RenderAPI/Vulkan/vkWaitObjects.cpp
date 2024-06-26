#include "pch.h"
#include "vkWaitObjects.h"

namespace mwengine::RenderAPI::Vulkan {
	vkSemaphore::vkSemaphore(Instance* instance) {
		this->instance = (vkInstance*) instance;

		VkSemaphoreCreateInfo createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
		createInfo.flags = 0;
		createInfo.pNext = nullptr;

		vkCreateSemaphore(this->instance->GetNativeDevice(), &createInfo, nullptr, &semaphore);
	}

	vkSemaphore::~vkSemaphore() {
		vkDestroySemaphore(instance->GetNativeDevice(), semaphore, nullptr);
	}

	VkSemaphore vkSemaphore::GetNativeSemaphore() {
		return semaphore;
	}

	vkFence::vkFence(Instance* instance, bool enabled) {
		this->instance = (vkInstance*) instance;

		VkFenceCreateInfo createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
		createInfo.flags = enabled ? VK_FENCE_CREATE_SIGNALED_BIT : 0;
		createInfo.pNext = nullptr;

		vkCreateFence(this->instance->GetNativeDevice(), &createInfo, nullptr, &fence);
	}

	vkFence::~vkFence() {
		vkDestroyFence(this->instance->GetNativeDevice(), fence, nullptr);
	}

	void vkFence::Reset() {
		vkResetFences(this->instance->GetNativeDevice(), 1, &fence);
	}

	void vkFence::WaitFor() {
		vkWaitForFences(this->instance->GetNativeDevice(), 1, &fence, true, UINT64_MAX);
	}

	VkFence vkFence::GetNativeFence() {
		return fence;
	}
}