#include "src/pch.h"
#include "Window.h"

namespace mwengine {
	class Camera {
	public:
		virtual ~Camera();

		virtual glm::mat4 GetProjectionMatrix() = 0;
		virtual glm::mat4 GetViewMatrix() = 0;
	};

	class OrthographicCamera : Camera {
	public:
		OrthographicCamera(glm::vec3 pos, glm::vec2 size, float rot);
		~OrthographicCamera();

		virtual glm::mat4 GetProjectionMatrix();
		virtual glm::mat4 GetViewMatrix();

		glm::vec3 pos;
		glm::vec2 size;
		float rot;
	};
}