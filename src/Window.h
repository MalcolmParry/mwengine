#pragma once

#include "pch.h"
#include "Event.h"
#include <string>

namespace mwengine {
	class Window {
	public:
		Window(glm::uvec2 size, const std::string& appName, const std::string& title);
		~Window();

		void Update();
		void SetCallback(EventCallback func);

		glm::uvec2 GetWindowSize();
		glm::uvec2 GetClientSize();

		void* GetHandle();
	private:
		EventCallback callback;
		void* handle;
	};
}