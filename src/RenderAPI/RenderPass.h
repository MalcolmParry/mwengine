#pragma once

#include "src/pch.h"
#include "Instance.h"

namespace mwengine::RenderAPI {
	class Display;

	class RenderPass {
	public:
		static RenderPass* Create(Instance* instance, Display* display);
		virtual ~RenderPass() {};

		virtual Instance* GetInstance() = 0;
	};
}