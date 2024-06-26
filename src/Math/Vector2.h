#pragma once

#include "../pch.h"

// All vectors
#define VecOpEq(type, op)								\
inline type<T>& operator op=(const type<T>& other) {	\
	*this = *this op other;								\
	return *this;										\
}

#define VecIndex()					\
inline T& operator[](uint8 i) {		\
	return ((T*) this)[i];			\
}

#define VecNormalize(type)			\
inline type<T> Normalize() {		\
	return *this / Length();		\
}

#define VecNotEq(type)								\
inline bool operator!=(const type<T>& other) {		\
	return !(*this == other);						\
}

#define VecInv(type)			\
inline type<T> operator-() {	\
	return *this * -1;			\
}

#define VecFunctions(type) VecOpEq(type, +) VecOpEq(type, -) VecOpEq(type, *) VecOpEq(type, /) VecNotEq(type) VecIndex() VecNormalize(type) VecInv(type)

// Vector2 only
#define Vec2VectorOp(op)									\
inline Vector2<T> operator op(const Vector2<T>& other) {	\
	return Vector2<T>(x op other.x, y op other.y);			\
}

#define Vec2SingularOp(op)							\
inline Vector2<T> operator op(const T other) {		\
	return Vector2<T>(x op other, y op other);		\
}

#define Vec2Op(op) Vec2VectorOp(op) Vec2SingularOp(op)

namespace mwengine::Math {
	template<typename T>
	class Vector2 {
	public:
		Vector2() { x = 0; y = 0; }
		Vector2(T all) { x = all; y = all; }
		Vector2(T x, T y) { this->x = x; this->y = y; }

		template<typename T2>
		Vector2(Vector2<T2>& other) { x = (T) other.x; y = (T) other.y; }

		Vec2Op(+);
		Vec2Op(-);
		Vec2Op(*);
		Vec2Op(/);
		Vec2Op(%);
		VecFunctions(Vector2);

		inline bool operator==(const Vector2<T>& other) {
			return x == other.x && y == other.y;
		}

		inline T Length() {
			return sqrt(x * x + y * y);
		}

		inline T Sum() {
			return x + y;
		}

		union {
			T x;
			T u;
		};

		union {
			T y;
			T v;
		};
	};

	template<typename T>
	inline T Dot(Vector2<T> a, Vector2<T> b) {
		return (a * b).Sum();
	}

	using Float2 = Vector2<float>;
	using UInt2 = Vector2<uint32>;
	using Int2 = Vector2<int32>;
}

namespace std {
	template<typename T>
	inline std::string to_string(mwengine::Math::Vector2<T> vector) {
		std::stringstream ss;
		ss << "(" << std::to_string(vector.x) << ", " << std::to_string(vector.y) << ")";
		return ss.str();
	}
}