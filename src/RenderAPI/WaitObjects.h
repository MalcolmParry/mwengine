#pragma once

#include "Instance.h"

namespace mwengine::RenderAPI {
	class Semaphore {
	public:
		static Semaphore* Create(Instance* instance);
		virtual ~Semaphore() {}
	};

	class Fence {
	public:
		static Fence* Create(Instance* instance, bool enabled = false);
		virtual ~Fence() {}

		virtual void Reset() = 0;
		virtual void WaitFor() = 0;
	};
}