#pragma once

#include "src/pch.h"
#include "Instance.h"
#include "Image.h"
#include "RenderPass.h"

namespace mwengine::RenderAPI {
	class Framebuffer {
	public:
		static Framebuffer* Create(Instance* instance, RenderPass* renderPass, Image* image, Image* depthImage = nullptr);
		virtual ~Framebuffer() {};

		virtual Instance* GetInstance() = 0;
		virtual Math::UInt2 GetSize() = 0;
	};
}