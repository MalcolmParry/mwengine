#pragma once

#include "src/Keycode.h"

namespace mwengine {
	uint8 MWToWinKey(Keycode code);
	Keycode WinToMWKey(uint8 code);
}