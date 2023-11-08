#include "pch.h"
#include "Camera.h"

namespace mwengine {
	Camera::~Camera() {

	}

	OrthographicCamera::OrthographicCamera(glm::vec3 pos, glm::vec2 size, float rot) {
		this->pos = pos;
		this->size = size;
		this->rot = rot;
	}

	OrthographicCamera::~OrthographicCamera() {

	}

	glm::mat4 OrthographicCamera::GetProjectionMatrix() {
		return glm::ortho<float>(-size.x / 2.0f, size.x / 2.0f, -size.y / 2.0f, size.y / 2.0f, -1, 1);
	}

	glm::mat4 OrthographicCamera::GetViewMatrix() {
		glm::mat4 transform = glm::translate(glm::mat4(1), pos) * glm::rotate(glm::mat4(1), rot, glm::vec3(0, 0, 1));
		return glm::inverse(transform);
	}
}