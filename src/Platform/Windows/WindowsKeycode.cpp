#include "pch.h"

#if (MW_PLATFORM == WINDOWS)

#include "WindowsKeycode.h"
#include "Keycode.h"
#include <Windows.h>

#define UNKNOWN 0x0E

namespace mwengine {
	static uint16 mwToWin[] = {
		UNKNOWN,
		VK_SPACE,
		VK_TAB,
		VK_CAPITAL,
		VK_SHIFT,
		VK_SHIFT,
		VK_CONTROL,
		VK_CONTROL,
		VK_MENU,
		VK_MENU,
		VK_BACK,
		VK_RETURN,
		VK_ESCAPE,
		VK_F1,
		VK_F2,
		VK_F3,
		VK_F4,
		VK_F5,
		VK_F6,
		VK_F7,
		VK_F8,
		VK_F9,
		VK_F10,
		VK_F11,
		VK_F12,
		VK_F13,
		VK_F14,
		VK_F15,
		VK_F16,
		VK_F17,
		VK_F18,
		VK_F19,
		VK_F20,
		VK_F21,
		VK_F22,
		VK_F23,
		VK_F24,
		UNKNOWN,
		0x30, // 0 key
		0x31,
		0x32,
		0x33,
		0x34,
		0x35,
		0x36,
		0x37,
		0x38,
		0x39, // 9 key
		0x41, // a key
		0x42,
		0x43,
		0x44,
		0x45,
		0x46,
		0x47,
		0x48,
		0x49,
		0x4A,
		0x4B,
		0x4C,
		0x4D,
		0x4E,
		0x4F,
		0x50,
		0x51,
		0x52,
		0x53,
		0x54,
		0x55,
		0x56,
		0x57,
		0x58,
		0x59, // z key
		0x5A,
		VK_OEM_4,
		VK_OEM_6,
		UNKNOWN,
		VK_OEM_1,
		VK_OEM_7,
		VK_OEM_COMMA,
		VK_OEM_PERIOD,
		VK_OEM_2,
		VK_SNAPSHOT,
		VK_SCROLL,
		VK_PAUSE,
		VK_INSERT,
		VK_HOME,
		VK_PRIOR,
		VK_DELETE,
		VK_END,
		VK_NEXT,
		VK_UP,
		VK_DOWN,
		VK_LEFT,
		VK_RIGHT,
		VK_NUMLOCK,
		VK_DIVIDE,
		VK_MULTIPLY,
		VK_SUBTRACT,
		VK_ADD,
		UNKNOWN,
		VK_DECIMAL,
		VK_NUMPAD0,
		VK_NUMPAD1,
		VK_NUMPAD2,
		VK_NUMPAD3,
		VK_NUMPAD4,
		VK_NUMPAD5,
		VK_NUMPAD6,
		VK_NUMPAD7,
		VK_NUMPAD8,
		VK_NUMPAD9,
	};

	uint8 MWToWinKey(Keycode code) {
		if (code >= 0 && code < KEY_LAST) {
			return mwToWin[code];
		}

		return UNKNOWN;
	}

	Keycode WinToMWKey(uint8 code) {
		for (uint16 i = 0; i < KEY_LAST; i++) {
			if (mwToWin[i] == code)
				return (Keycode) i;
		}

		return KEY_UNKNOWN;
	}
}

#endif