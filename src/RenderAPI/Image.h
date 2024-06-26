#pragma once

#include "src/pch.h"
#include "Instance.h"

namespace mwengine::RenderAPI {
	class Image {
	public:
		static Image* Create(Instance* instance, Math::UInt2 size);
		virtual ~Image() {};

		virtual void SetData(void* data) = 0;
		virtual Instance* GetInstance() = 0;
		virtual uint32 GetSize() = 0;
		virtual Math::UInt2 GetResolution() = 0;
	};

	class Texture {
	public:
		static Texture* Create(Instance* instance, Image* image, bool pixelated = false);
		virtual ~Texture() {};

		virtual Instance* GetInstance() = 0;
		virtual Image* GetImage() = 0;
	};
}