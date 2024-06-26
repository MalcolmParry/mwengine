#pragma once

#include <cmath>
#include "Vector4.h"

#define PI 3.141592653589793
#define TAU (Pi * 2)

namespace mwengine::Math {
	template<typename T>
	inline T Sin(T x) {
		return sin(x);
	}

	template<typename T>
	inline T Cos(T x) {
		return cos(x);
	}

	template<typename T>
	inline T Tan(T x) {
		return tan(x);
	}

	template<typename T>
	inline T Asin(T x) {
		return asin(x);
	}

	template<typename T>
	inline T Acos(T x) {
		return acos(x);
	}

	template<typename T>
	inline T Atan(T x) {
		return atan(x);
	}

	template<typename T>
	inline Vector3<T> DirectionToEulerAngles(Vector3<T>& direction) {
		Vector3<T> result;

		// todo

		return result;
	}

	template<typename T>
	inline T Radians(T degrees) {
		return degrees / 180 * PI;
	}

	template<typename T>
	inline T Degrees(T radians) {
		return radians * 180 / PI;
	}

	template<typename T>
	inline T Min(T min, T value) {
		return ((value < min) ? min : value);
	}

	template<typename T>
	inline T Max(T max, T value) {
		return ((value > max) ? max : value);
	}

	template<typename T>
	inline T Clamp(T min, T max, T value) {
		return Min<T>(min, Max<T>(max, value));
	}
}