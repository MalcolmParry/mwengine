#include "src/pch.h"

namespace mwengine {
	class Camera {
	public:
		virtual ~Camera();

		virtual Math::Float4x4 GetProjectionMatrix() = 0;
		virtual Math::Float4x4 GetViewMatrix() = 0;
	};

	class OrthographicCamera : Camera {
	public:
		OrthographicCamera(Math::Float3 pos, Math::Float3 size, float rot);
		virtual ~OrthographicCamera();

		virtual Math::Float4x4 GetProjectionMatrix();
		virtual Math::Float4x4 GetViewMatrix();

		Math::Float3 pos;
		Math::Float3 size;
		Math::Float3 rot;
	};

	class PerspectiveCamera : Camera {
	public:
		PerspectiveCamera(float aspectRatio = 1.0f, float fov = Math::Radians(60.0f));
		virtual ~PerspectiveCamera();

		virtual Math::Float4x4 GetProjectionMatrix();
		virtual Math::Float4x4 GetViewMatrix();

		float aspectRatio;
		float fov;
		Math::Float3 pos;
		Math::Float3 rot;
	};
}