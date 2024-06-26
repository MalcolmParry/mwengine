#pragma once

#include "../pch.h"
#include "Vector3.h"

#define Vec4VectorOp(op)														\
inline Vector4<T> operator op(const Vector4<T>& other) {						\
	return Vector4<T>(x op other.x, y op other.y, z op other.z, w op other.w);	\
}

#define Vec4SingularOp(op)													\
inline Vector4<T> operator op(const T other) {								\
	return Vector4<T>(x op other, y op other, z op other, w op other);		\
}

#define Vec4Op(op) Vec4VectorOp(op) Vec4SingularOp(op)

namespace mwengine::Math {
	template<typename T>
	class Vector4 {
	public:
		Vector4() { x = 0; y = 0; z = 0; w = 0; }
		Vector4(T all) { x = all; y = all; z = all; w = all; }
		Vector4(T x, T y, T z, T w) { this->x = x; this->y = y; this->z = z; this->w = w; }
		Vector4(const Vector2<T>& xy, const Vector2<T>& zw) { x = xy.x; y = xy.y; z = zw.z; w = zw.w; }
		Vector4(const Vector3<T>& xyz, T w = 1) { x = xyz.x; y = xyz.y; z = xyz.z; this->w = w; }

		template<typename T2>
		Vector4(Vector4<T2>& other) { x = other.x; y = other.y; z = other.z; w = other.w; }

		Vec4Op(+);
		Vec4Op(-);
		Vec4Op(*);
		Vec4Op(/);
		Vec4Op(%);
		VecFunctions(Vector4);

		inline bool operator==(const Vector4<T>& other) {
			return x == other.x && y == other.y && z == other.z && w == other.w;
		}

		inline T Length() {
			return sqrt(x * x + y * y + z * z + w * w);
		}

		inline T Sum() {
			return x + y + z + w;
		}

		union {
			T x;
			T u;
			T r;
		};

		union {
			T y;
			T v;
			T g;
		};

		union {
			T z;
			T b;
		};

		union {
			T w;
			T a;
		};
	};

	template<typename T>
	inline T Dot(Vector4<T> a, Vector4<T> b) {
		return (a * b).Sum();
	}

	using Float4 = Vector4<float>;
	using UInt4 = Vector4<uint32>;
	using Int4 = Vector4<int32>;
}

namespace std {
	template<typename T>
	inline std::string to_string(mwengine::Math::Vector4<T> vector) {
		std::stringstream ss;
		ss << "(" << std::to_string(vector.x) << ", " << std::to_string(vector.y) << ", " << std::to_string(vector.z) << ", " << std::to_string(vector.w) << ")";
		return ss.str();
	}
}