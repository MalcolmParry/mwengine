#pragma once

#include "src/pch.h"

namespace mwengine {
	class Transform {
	public:
		Transform(Math::Float3 pos = Math::Float3(0, 0, 0), Math::Float3 size = Math::Float3(1, 1, 1), Math::Float3 rot = Math::Float3(0, 0, 0));

		Math::Float4x4 GetMatrix();

		Math::Float3 pos;
		Math::Float3 size;
		Math::Float3 rot;
	};
}