#pragma once

#include "Instance.h"
#include "Framebuffer.h"
#include "WaitObjects.h"
#include "RenderPass.h"

namespace mwengine::RenderAPI {
	class RenderPass;

	class Display {
	public:
		static Display* Create(Instance* instance, Window* window = nullptr);
		virtual ~Display() {};

		virtual void Rebuild() = 0;

		virtual Instance* GetInstance() = 0;
		virtual void SetRenderPass(RenderPass* renderPass) = 0;
		virtual uint32 GetNextFramebufferIndex(Semaphore* signalSemaphore, Fence* signalFence) = 0;
		virtual Framebuffer* GetFramebuffer(uint32 i) = 0;
		virtual void PresentFramebuffer(uint32 framebufferIndex, Semaphore* waitSemaphore) = 0;

		static constexpr uint32 NoImage = UINT32_MAX;
	};
}