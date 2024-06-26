#pragma once

#include "vkInstance.h"
#include "../WaitObjects.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkSemaphore : Semaphore {
	public:
		vkSemaphore(Instance* instance);
		virtual ~vkSemaphore();

		VkSemaphore GetNativeSemaphore();
	private:
		vkInstance* instance;
		VkSemaphore semaphore;
	};

	class vkFence : Fence {
	public:
		vkFence(Instance* instance, bool enabled = false);
		virtual ~vkFence();

		virtual void Reset();
		virtual void WaitFor();

		VkFence GetNativeFence();
	private:
		vkInstance* instance;
		VkFence fence;
	};
}