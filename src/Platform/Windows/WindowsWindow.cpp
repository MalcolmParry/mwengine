#include "pch.h"

#ifdef MW_WINDOWS

#include "src/Window.h"
#include "WindowsKeycode.h"
#include <Windows.h>

namespace mwengine {
	static bool keysDown[Keycode::Last + 1];
	static bool mouseButtonsDown[MouseCode::Last + 1];
	static glm::uvec2 mousePos(0, 0);

	static EventCallback sCallback;

	LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
		EventCallback callback = sCallback;

		switch (uMsg) {
			// Application Event

		case WM_SIZE:
			callback(WindowResizeEvent(
				glm::uvec2(
					LOWORD(lParam),
					HIWORD(lParam)
				)
			));

			return 0;
		case WM_SETFOCUS:
			callback(WindowFocusEvent());

			return 0;
		case WM_KILLFOCUS:
			callback(WindowLostFocusEvent());

			return 0;
		case WM_MOVE:
			callback(WindowMovedEvent(
				glm::uvec2(
					LOWORD(lParam),
					HIWORD(lParam)
				)
			));

			return 0;
		case WM_CLOSE:
			callback(WindowClosedEvent());

			return 0;

			// Keyboard Events

		case WM_SYSKEYDOWN:
		case WM_KEYDOWN:
			keysDown[WinToMWKey(wParam)] = true;

			callback(KeyDownEvent(
				WinToMWKey(wParam),
				(HIWORD(lParam) & KF_REPEAT) == KF_REPEAT
			));

			return 0;
		case WM_KEYUP:
			keysDown[WinToMWKey(wParam)] = false;

			callback(KeyUpEvent(
				WinToMWKey(wParam)
			));

			return 0;
		case WM_CHAR:
			if (wParam == 0x1B) // do not register escape as KeyTextEvent
				return 0;

			callback(KeyCharEvent(
				(char) wParam
			));

			return 0;

			// Mouse Button Pressed Event

		case WM_LBUTTONDOWN:
			mouseButtonsDown[MouseCode::Left] = true;

			callback(MouseDownEvent(
				MouseCode::Left
			));

			return 0;
		case WM_RBUTTONDOWN:
			mouseButtonsDown[MouseCode::Right] = true;

			callback(MouseDownEvent(
				MouseCode::Right
			));

			return 0;
		case WM_MBUTTONDOWN:
			mouseButtonsDown[MouseCode::Middle] = true;

			callback(MouseDownEvent(
				MouseCode::Middle
			));

			return 0;

			// Mouse Button Released Event

		case WM_LBUTTONUP:
			mouseButtonsDown[MouseCode::Left] = false;

			callback(MouseUpEvent(
				MouseCode::Left
			));

			return 0;
		case WM_RBUTTONUP:
			mouseButtonsDown[MouseCode::Right] = false;

			callback(MouseUpEvent(
				MouseCode::Right
			));

			return 0;
		case WM_MBUTTONUP:
			mouseButtonsDown[MouseCode::Middle] = false;

			callback(MouseUpEvent(
				MouseCode::Middle
			));

			return 0;

		case WM_MOUSEMOVE:
			mousePos = glm::uvec2(
				LOWORD(lParam),
				HIWORD(lParam)
			);

			callback(MouseMovedEvent(
				mousePos
			));

			return 0;
		case WM_PAINT:
			PAINTSTRUCT ps;
			HDC hdc = BeginPaint(hwnd, &ps);

			FillRect(hdc, &ps.rcPaint, (HBRUSH) (COLOR_WINDOW + 1));

			EndPaint(hwnd, &ps);
			return 0;
		}

		return DefWindowProc(hwnd, uMsg, wParam, lParam);
	}

	void DefCallback(Event& event) {}

	Window::Window(glm::uvec2 size, const std::string& appName, const std::string& title) {
		SetCallback(DefCallback);

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

		ShowWindow((HWND) handle, SW_SHOW);
	}

	Window::~Window() {
		DestroyWindow((HWND) handle);
	}

	void Window::Update() {
		sCallback = callback;

		MSG msg = {};
		while (PeekMessage(&msg, (HWND) handle, 0, 0, PM_REMOVE)) {
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
	}

	void Window::SetCallback(EventCallback func) {
		callback = func;
		sCallback = func;
	}

	glm::uvec2 Window::GetWindowSize() {
		LPRECT rect = new RECT();
		GetWindowRect((HWND) handle, rect);
		return glm::uvec2(rect->right - rect->left, rect->bottom - rect->top);
    }

	glm::uvec2 Window::GetClientSize() {
		LPRECT rect = new RECT();
		GetClientRect((HWND) handle, rect);
		return glm::uvec2(rect->right - rect->left, rect->bottom - rect->top);
    }

    void* Window::GetHandle() {
        return handle;
    }
}

#endif