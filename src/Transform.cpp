#include "pch.h"
#include "Transform.h"

namespace mwengine {
	Transform::Transform(Math::Float3 pos, Math::Float3 size, Math::Float3 rot) {
		this->pos = pos;
		this->size = size;
		this->rot = rot;
	}

	Math::Float4x4 Transform::GetMatrix() {
		return Math::Translate(pos) * Math::RotateXYZ(rot) * Math::Scale(size);
	}
}