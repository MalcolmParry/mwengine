#pragma once

#include "Core.h"
#include "Event.h"
#include "MWATH.h"
#include <string>

namespace mwengine {
	class Window {
	public:
		Window(MWATH::Int2 size, const std::string title);
		~Window();

		void Update();
		void SetCallback(EventCallback func);

		MWATH::Int2 GetWindowSize();
		MWATH::Int2 GetClientSize();

		void* GetHandle();
	private:
		EventCallback callback;
		void* handle;
	};
}