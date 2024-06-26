#pragma once

#include "Matrix4x4.h"
#include "Trigonometry.h"

namespace mwengine::Math {
	template<typename T>
	Matrix4x4<T> Translate(const Vector3<T>& translation) {
		Matrix4x4<T> result;

		result[3][0] = translation.x;
		result[3][1] = translation.y;
		result[3][2] = translation.z;

		return result;
	}

	template<typename T>
	Matrix4x4<T> Scale(const Vector3<T>& size) {
		Matrix4x4<T> result;

		result[0][0] = size.x;
		result[1][1] = size.y;
		result[2][3] = size.z;

		return result;
	}

	template<typename T>
	Matrix4x4<T> RotateX(T angle) {
		Matrix4x4<T> result;

		T cosAngle = Cos(angle);
		T sinAngle = Sin(angle);

		result[1][1] = cosAngle;
		result[1][2] = sinAngle;
		result[2][1] = -sinAngle;
		result[2][2] = cosAngle;

		return result;
	}

	template<typename T>
	Matrix4x4<T> RotateY(T angle) {
		Matrix4x4<T> result;

		T cosAngle = Cos(angle);
		T sinAngle = Sin(angle);

		result[0][0] = cosAngle;
		result[2][0] = sinAngle;
		result[0][2] = -sinAngle;
		result[2][2] = cosAngle;

		return result;
	}

	template<typename T>
	Matrix4x4<T> RotateZ(T angle) {
		Matrix4x4<T> result;

		T cosAngle = Cos(angle);
		T sinAngle = Sin(angle);

		result[0][0] = cosAngle;
		result[0][1] = sinAngle;
		result[1][0] = -sinAngle;
		result[1][1] = cosAngle;

		return result;
	}

	template<typename T>
	Matrix4x4<T> RotateXYZ(Vector3<T> eulerAnglesXYZ) {
		return RotateZ(eulerAnglesXYZ.z) * RotateY(eulerAnglesXYZ.y) * RotateX(eulerAnglesXYZ.x);
	}

	template<typename T>
	Matrix4x4<T> LookAt(Vector3<T>& eye, Vector3<T>& center) {
		Matrix4x4<T> result(1);

		Vector3<T> f = (center - eye).Normalize();
		Vector3<T> s = Vector3<T>(Cross<T>(f, MW_VECTOR_UP)).Normalize();
		Vector3<T> u = Cross<T>(s, f);

		result[0][0] = s.x;
		result[1][0] = s.y;
		result[2][0] = s.z;
		result[0][1] = u.x;
		result[1][1] = u.y;
		result[2][1] = u.z;
		result[0][2] = -f.x;
		result[1][2] = -f.y;
		result[2][2] = -f.z;
		result[3][0] = -Dot(s, eye);
		result[3][1] = -Dot(u, eye);
		result[3][2] = Dot(f, eye);

		return result;
	}

	template<typename T>
	Matrix4x4<T> Orthographic(T left, T right, T bottom, T top, T near, T far) {
		Matrix4x4<T> result(1);

		result[0][0] = 2 / (right - left);
		result[1][1] = 2 / (top - bottom);
		result[2][2] = -1 / (far - near);
		result[3][0] = -(right + left) / (right - left);
		result[3][1] = -(top + bottom) / (top - bottom);
		result[3][2] = -near / (far - near);

		return result;
	}

	template<typename T>
	Matrix4x4<T> Perspective(T aspectRatio, T fov, T near, T far) {
		Matrix4x4<T> result(0);

		T tanHalfFov = Tan(fov / 2);

		result[0][0] = 1 / (aspectRatio * tanHalfFov);
		result[1][1] = -1 / tanHalfFov;
		result[2][2] = far / (near - far);
		result[2][3] = -1;
		result[3][2] = -(far * near) / (far - near);

		return result;
	}
}