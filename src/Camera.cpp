#include "pch.h"
#include "Camera.h"

namespace mwengine {
	Camera::~Camera() {

	}

	OrthographicCamera::OrthographicCamera(Math::Float3 pos, Math::Float3 size, float rot) {
		this->pos = pos;
		this->size = size;
		this->rot = rot;
	}

	OrthographicCamera::~OrthographicCamera() {

	}

	Math::Float4x4 OrthographicCamera::GetProjectionMatrix() {
		Math::Float4x4 result = Math::Orthographic<float>(-size.x / 2.0f, size.x / 2.0f, -size.y / 2.0f, size.y / 2.0f, -1, 1);
		return result;
	}

	Math::Float4x4 OrthographicCamera::GetViewMatrix() {
		Math::Float4x4 transform = Math::Translate(pos) * Math::RotateXYZ(rot);
		return -transform;
	}

    PerspectiveCamera::PerspectiveCamera(float aspectRatio, float fov) {
		this->aspectRatio = aspectRatio;
		this->fov = fov;
		this->pos = {};
		this->rot = {};
    }

    PerspectiveCamera::~PerspectiveCamera() {

    }

	Math::Float4x4 PerspectiveCamera::GetProjectionMatrix() {
		return Math::Perspective(aspectRatio, fov, 0.1f, 100.0f);
    }

    Math::Float4x4 PerspectiveCamera::GetViewMatrix() {
		return Math::LookAt(pos, pos + Math::Float3(Math::RotateXYZ(rot) * (Math::Float4) MW_VECTOR_FORWARD));
    }
}