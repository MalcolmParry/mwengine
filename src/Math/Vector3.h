#pragma once

#include "../pch.h"
#include "Vector2.h"

#define Vec3VectorOp(op)											\
inline Vector3<T> operator op(const Vector3<T>& other) {			\
	return Vector3<T>(x op other.x, y op other.y, z op other.z);	\
}

#define Vec3SingularOp(op)										\
inline Vector3<T> operator op(const T other) {					\
	return Vector3<T>(x op other, y op other, z op other);		\
}

#define Vec3Op(op) Vec3VectorOp(op) Vec3SingularOp(op)

namespace mwengine::Math {
	template<typename T>
	class Vector4;

	template<typename T>
	class Vector3 {
	public:
		Vector3() { x = 0; y = 0; z = 0; }
		Vector3(T all) { x = all; y = all; z = all; }
		Vector3(T x, T y, T z) { this->x = x; this->y = y; this->z = z; }
		Vector3(const Vector2<T>& xy, T z) { x = xy.x; y = xy.y; this->z = z; }
		Vector3(const Vector4<T>& xyzw) { x = xyzw.x; y = xyzw.y; z = xyzw.z; }

		template<typename T2>
		Vector3(Vector3<T2>& other) { x = other.x; y = other.y; z = other.z; }

		Vec3Op(+);
		Vec3Op(-);
		Vec3Op(*);
		Vec3Op(/);
		VecFunctions(Vector3);

		inline bool operator==(const Vector3<T>& other) {
			return x == other.x && y == other.y && z == other.z;
		}

		inline T Length() {
			return sqrt(x * x + y * y + z * z);
		}

		inline T Sum() {
			return x + y + z;
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
	};

	template<typename T>
	inline T Dot(Vector3<T> a, Vector3<T> b) {
		return (a * b).Sum();
	}

	template<typename T>
	inline Vector3<T> Cross(Vector3<T> a, Vector3<T> b) {
		return Vector3<T>(
			a.y * b.z - a.z * b.y,
			a.z * b.x - a.x * b.z,
			a.x * b.y - a.y * b.x
		);
	}

	using Float3 = Vector3<float>;
	using UInt3 = Vector3<uint32>;
	using Int3 = Vector3<int32>;
}

namespace std {
	template<typename T>
	inline std::string to_string(mwengine::Math::Vector3<T> vector) {
		std::stringstream ss;
		ss << "(" << std::to_string(vector.x) << ", " << std::to_string(vector.y) << ", " << std::to_string(vector.z) << ")";
		return ss.str();
	}
}

#define MW_VECTOR_FORWARD	Math::Float3(0, 0, -1)
#define MW_VECTOR_UP		Math::Float3(0, 1, 0)
#define MW_VECTOR_RIGHT		Math::Float3(1, 0, 0)