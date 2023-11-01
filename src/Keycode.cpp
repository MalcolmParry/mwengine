#include "pch.h"

#include "Keycode.h"

namespace mwengine {
	static const std::string keyNames[] = {
		"Unknown",
		"Space",
		"Tab",
		"CapsLock",
		"LShift",
		"RShift",
		"LControl",
		"RControl",
		"LAlt",
		"RAlt",
		"Backspace",
		"Enter",
		"Escape",
		"F1",
		"F2",
		"F3",
		"F4",
		"F5",
		"F6",
		"F7",
		"F8",
		"F9",
		"F10",
		"F11",
		"F12",
		"F13",
		"F14",
		"F15",
		"F16",
		"F17",
		"F18",
		"F19",
		"F20",
		"F21",
		"F22",
		"F23",
		"F24",
		"F25",
		"Alpha0",
		"Alpha1",
		"Alpha2",
		"Alpha3",
		"Alpha4",
		"Alpha5",
		"Alpha6",
		"Alpha7",
		"Alpha8",
		"Alpha9",
		"A",
		"B",
		"C",
		"D",
		"E",
		"F",
		"G",
		"H",
		"I",
		"J",
		"K",
		"L",
		"M",
		"N",
		"O",
		"P",
		"Q",
		"R",
		"S",
		"T",
		"U",
		"V",
		"W",
		"X",
		"Y",
		"Z",
		"LBracket",
		"RBracket",
		"Hash",
		"Semicolon",
		"Apostrophe",
		"Comma",
		"Period",
		"Slash",
		"PrintScreen",
		"ScrollLock",
		"Pause",
		"Insert",
		"Home",
		"PageUp",
		"Delete",
		"End",
		"PageDown",
		"Up",
		"Down",
		"Left",
		"Right",
		"NumLock",
		"KeypadDivide",
		"KeypadMultiply",
		"KeypadSubtract",
		"KeypadAdd",
		"KeypadEnter",
		"KeypadDecimal",
		"Keypad0",
		"Keypad1",
		"Keypad2",
		"Keypad3",
		"Keypad4",
		"Keypad5",
		"Keypad6",
		"Keypad7",
		"Keypad8",
		"Keypad9"
	};

	static const std::string mouseNames[] = {
		"Unknown",
		"1",
		"2",
		"3",
		"4",
		"5",
		"6",
		"7",
		"8"
	};

	const std::string GetKeycodeName(Keycode code) {
		if (code < 0 || code > Keycode::Last)
			code = Keycode::Unknown;

		return keyNames[code];
	}

	const std::string GetMousecodeName(MouseCode code) {
		if (code < 0 || code > MouseCodes::Last)
			code = MouseCodes::Unknown;

		return mouseNames[code];
	}
}