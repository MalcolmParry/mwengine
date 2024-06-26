#pragma once

#include "pch.h"
#include "Event.h"
#include <string>

namespace mwengine {
	enum WindowState : uint8 {
		WINDOW_STATE_SHOWN,
		WINDOW_STATE_HIDDEN,
		WINDOW_STATE_MAXIMIZED,
		WINDOW_STATE_MINIMIZED
	};

	enum CursorType : uint8 {
		CURSOR_TYPE_ARROW,
		CURSOR_TYPE_IBEAM,
		CURSOR_TYPE_HAND,
		CURSOR_TYPE_LOADING,
		CURSOR_TYPE_HIDDEN
	};

	class Window {
	public:
		Window(Math::UInt2 size, const std::string& appName, const std::string& title, void* userPtr = nullptr);
		~Window();

		void Update();
		void SetCallback(EventCallback func);
		EventCallback GetCallback();

		Math::UInt2 GetWindowSize();
		Math::UInt2 GetClientSize();
		bool GetKeyDown(Keycode keycode);
		bool GetMouseDown(MouseCode mousecode);
		Math::UInt2 GetMousePos();
		void SetMousePos(Math::UInt2 pos);
		void SetWindowState(WindowState windowState);

		void* GetHandle();

		void* userPtr;
		CursorType cursorType;

		bool _keysDown[KEY_LAST + 1];
		bool _mouseDown[KEY_LAST + 1];
		Math::UInt2 _mousePos;

		// Moving window
		Math::Int2 _movingMousePos;
	private:
		EventCallback callback;
		void* handle;
	};

	void HideConsole();
	void ShowConsole();
	bool IsConsoleVisible();
}