#include "pch.h"

#if (MW_PLATFORM == WINDOWS)

#include "src/Window.h"
#include "WindowsKeycode.h"
#include <Windows.h>
#include <hidusage.h>

namespace mwengine {
	Window* window = nullptr;

	LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
		EventCallback callback = window->GetCallback();
		void* userPtr = window->userPtr;

		switch (uMsg) {
			// Application Event

		case WM_SIZE:
			callback(userPtr, WindowResizeEvent(
				Math::UInt2(
					LOWORD(lParam),
					HIWORD(lParam)
				)
			));

			return 0;
		case WM_SETFOCUS:
			callback(userPtr, WindowFocusEvent());

			return 0;
		case WM_KILLFOCUS:
			callback(userPtr, WindowLostFocusEvent());

			return 0;
		case WM_MOVE:
			callback(userPtr, WindowMovedEvent(
				Math::UInt2(
					LOWORD(lParam),
					HIWORD(lParam)
				)
			));

			return 0;
		case WM_CLOSE:
			callback(userPtr, WindowClosedEvent());

			return 0;

			// Keyboard Events

		case WM_SYSKEYDOWN:
		case WM_KEYDOWN:
			window->_keysDown[WinToMWKey(wParam)] = true;

			callback(userPtr, KeyDownEvent(
				WinToMWKey(wParam),
				(HIWORD(lParam) & KF_REPEAT) == KF_REPEAT
			));

			return 0;
		case WM_KEYUP:
			window->_keysDown[userPtr, WinToMWKey(wParam)] = false;

			callback(userPtr, KeyUpEvent(
				WinToMWKey(wParam)
			));

			return 0;
		case WM_CHAR:
			if (wParam == 0x1B) // do not register escape as KeyCharEvent
				return 0;

			callback(userPtr, KeyCharEvent(
				(char) wParam
			));

			return 0;

			// Mouse Button Pressed Event

		case WM_LBUTTONDOWN:
			window->_mouseDown[MOUSE_LEFT] = true;

			callback(userPtr, MouseDownEvent(
				MOUSE_LEFT
			));

			return 0;
		case WM_RBUTTONDOWN:
			window->_mouseDown[MOUSE_RIGHT] = true;

			callback(userPtr, MouseDownEvent(
				MOUSE_RIGHT
			));

			return 0;
		case WM_MBUTTONDOWN:
			window->_mouseDown[MOUSE_MIDDLE] = true;

			callback(userPtr, MouseDownEvent(
				MOUSE_MIDDLE
			));

			return 0;

			// Mouse Button Released Event

		case WM_LBUTTONUP:
			window->_mouseDown[MOUSE_LEFT] = false;

			callback(userPtr, MouseUpEvent(
				MOUSE_LEFT
			));

			return 0;
		case WM_RBUTTONUP:
			window->_mouseDown[MOUSE_RIGHT] = false;

			callback(userPtr, MouseUpEvent(
				MOUSE_RIGHT
			));

			return 0;
		case WM_MBUTTONUP:
			window->_mouseDown[MOUSE_MIDDLE] = false;

			callback(userPtr, MouseUpEvent(
				MOUSE_MIDDLE
			));

			return 0;

		case WM_MOUSEMOVE:
			window->_mousePos = Math::UInt2(
				LOWORD(lParam),
				HIWORD(lParam)
			);

			callback(userPtr, MouseMovedEvent(
				window->_mousePos
			));

			return 0;
		case WM_INPUT:
		{
			UINT dwSize = sizeof(RAWINPUT);
			static BYTE lpb[sizeof(RAWINPUT)];

			GetRawInputData((HRAWINPUT) lParam, RID_INPUT, lpb, &dwSize, sizeof(RAWINPUTHEADER));

			RAWINPUT* raw = (RAWINPUT*) lpb;

			if (raw->header.dwType != RIM_TYPEMOUSE)
				return 0;

			if (raw->data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE)
				return 0;

			int x = raw->data.mouse.lLastX;
			int y = raw->data.mouse.lLastY;
			
			if (x == 0 && y == 0) {
				return 0;
			}

			callback(userPtr, MouseRawMovedEvent(
				{ x, y }
			));

			return 0;
		}
		case WM_SETCURSOR:
			if (LOWORD(lParam) == HTCLIENT) {
				LPCTSTR cursor;

				switch (window->cursorType) {
				case CURSOR_TYPE_ARROW:
					cursor = IDC_ARROW;
					break;
				case CURSOR_TYPE_IBEAM:
					cursor = IDC_IBEAM;
					break;
				case CURSOR_TYPE_HAND:
					cursor = IDC_HAND;
					break;
				case CURSOR_TYPE_LOADING:
					cursor = IDC_WAIT;
					break;
				case CURSOR_TYPE_HIDDEN:
					SetCursor(NULL);
					return 0;
				default:
					MW_WARN("{0} is not a valid cursor type.", window->cursorType);
					cursor = IDC_WAIT;
				}

				SetCursor(LoadCursor(NULL, cursor));
			}
		}

		return DefWindowProc(hwnd, uMsg, wParam, lParam);
	}

	void DefCallback(void* userPtr, Event& event) {}

	Window::Window(Math::UInt2 size, const std::string& appName, const std::string& title, void* userPtr) {
		window = this;
		this->callback = DefCallback;
		this->userPtr = userPtr;
		cursorType = CURSOR_TYPE_ARROW;
		memset(_keysDown, 0, sizeof(_keysDown));
		memset(_mouseDown, 0, sizeof(_mouseDown));

		RECT rect = {
			0,
			0,
			size.x,
			size.y
		};

		AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, false);

		std::wstring wtitle(title.size() + 1, L'#');
		mbstowcs(&wtitle[0], title.c_str(), title.size() + 1);

		std::wstring wAppName(appName.size() + 1, L'#');
		mbstowcs(&wAppName[0], appName.c_str(), appName.size() + 1);

		WNDCLASS wc = {};

		wc.lpfnWndProc = WindowProc;
		wc.hInstance = GetModuleHandle(nullptr);
		wc.lpszClassName = wAppName.c_str();
		wc.style = CS_OWNDC;

		MW_ASSERT(RegisterClass(&wc), "Window class failed to register.");

		handle = CreateWindowExW(
			0,
			wAppName.c_str(),
			wtitle.c_str(),
			WS_OVERLAPPEDWINDOW,
			CW_USEDEFAULT,
			CW_USEDEFAULT,
			rect.right,
			rect.bottom,
			NULL,
			NULL,
			GetModuleHandle(nullptr),
			NULL
		);

		MW_ASSERT(handle != nullptr, "Window failed to create.");

		RAWINPUTDEVICE rid {};
		rid.usUsagePage = HID_USAGE_PAGE_GENERIC;
		rid.usUsage = HID_USAGE_GENERIC_MOUSE;
		rid.dwFlags = RIDEV_INPUTSINK;
		rid.hwndTarget = (HWND) handle;
		RegisterRawInputDevices(&rid, 1, sizeof(RAWINPUTDEVICE));
	}

	Window::~Window() {
		DestroyWindow((HWND) handle);
	}

	void Window::Update() {
		window = this;

		MSG msg = {};
		while (PeekMessage(&msg, (HWND) handle, 0, 0, PM_REMOVE)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}

	void Window::SetCallback(EventCallback func) {
		window = this;
		callback = func;
	}

	EventCallback Window::GetCallback() {
		return callback;
	}

	Math::UInt2 Window::GetWindowSize() {
		RECT rect;
		GetWindowRect((HWND) handle, &rect);
		return Math::UInt2(rect.right - rect.left, rect.bottom - rect.top);
    }

	Math::UInt2 Window::GetClientSize() {
		RECT rect;
		GetClientRect((HWND) handle, &rect);
		return Math::UInt2(rect.right - rect.left, rect.bottom - rect.top);
    }

	bool Window::GetKeyDown(Keycode keycode) {
		return _keysDown[keycode];
	}

	bool Window::GetMouseDown(MouseCode mousecode) {
		return _mouseDown[mousecode];
	}

	Math::UInt2 Window::GetMousePos() {
		return _mousePos;
	}

	void Window::SetMousePos(Math::UInt2 pos) {
		SetCursorPos(pos.x, pos.y);
	}

	void Window::SetWindowState(WindowState windowState) {
		int cmd = 0;
		switch (windowState) {
		case WINDOW_STATE_SHOWN:
			cmd = SW_SHOW;
			break;
		case WINDOW_STATE_HIDDEN:
			cmd = SW_HIDE;
			break;
		case WINDOW_STATE_MAXIMIZED:
			cmd = SW_MAXIMIZE;
			break;
		case WINDOW_STATE_MINIMIZED:
			cmd = SW_MINIMIZE;
			break;
		default:
			MW_ERROR("{0} is not a valid window state.", windowState);
		}

		ShowWindow((HWND) handle, cmd);
	}

    void* Window::GetHandle() {
        return handle;
    }

	void HideConsole() {
		ShowWindow(GetConsoleWindow(), SW_HIDE);
	}

	void ShowConsole() {
		ShowWindow(GetConsoleWindow(), SW_SHOW);
	}

	bool IsConsoleVisible() {
		return IsWindowVisible(GetConsoleWindow()) != FALSE;
	}
}

#endif