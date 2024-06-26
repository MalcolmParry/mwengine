#pragma once

#include "Vector4.h"

namespace mwengine::Math {
	template<typename T>
	class Matrix4x4 {
	public:
		Matrix4x4() {
			for (uint8 x = 0; x < 4; x++) {
				for (uint8 y = 0; y < 4; y++) {
					if (x == y)
						data[x][y] = 1;
					else
						data[x][y] = 0;
				}
			}
		}

		Matrix4x4(T all) {
			for (uint8 x = 0; x < 4; x++) {
				for (uint8 y = 0; y < 4; y++) {
					data[x][y] = all;
				}
			}
		}

		inline Matrix4x4<T> operator*(Matrix4x4<T>& other) {
			Matrix4x4<T> result(0);

			for (uint8 x = 0; x < 4; x++) {
				for (uint8 y = 0; y < 4; y++) {
					result[x][y] = Dot(GetRow(y), other.GetColumn(x));
				}
			}

			return result;
		}

		inline Matrix4x4<T>& operator*=(Matrix4x4<T>& other) {
			*this = *this * other;
			return *this;
		}

		inline Vector4<T> operator*(Vector4<T>& other) {
			Matrix4x4<T> resultM(0);

			for (uint8 i = 0; i < 4; i++) {
				resultM[i] = GetColumn(i) * other[i];
			}

			Vector4<T> result(0);
			for (uint8 i = 0; i < 4; i++) {
				result[i] = resultM.GetRow(i).Sum();
			}

			return result;
		}

		inline Matrix4x4<T> operator*(T scaler) {
			Matrix4x4<T> result(*this);

			for (uint8 x = 0; x < 4; x++) {
				for (uint8 y = 0; y < 4; y++) {
					result[x][y] *= scaler;
				}
			}

			return result;
		}

		inline Vector4<T> GetColumn(uint8 i) {
			return (*this)[i];
		}

		inline Vector4<T> GetRow(uint8 i) {
			Vector4<T> result(0);

			for (uint8 x = 0; x < 4; x++) {
				result[x] = data[x][i];
			}

			return result;
		}

		inline Vector4<T>& operator[](uint8 i) {
			return data[i];
		}

		inline bool operator==(Matrix4x4<T>& other) {
			for (uint8 i = 0; i < 4; i++) {
				if ((*this)[i] != other[i])
					return false;
			}

			return true;
		}

		inline bool operator!=(Matrix4x4<T>& other) {
			return !(*this == other);
		}

		inline Matrix4x4<T> operator-() {
			T Coef00 = data[2][2] * data[3][3] - data[3][2] * data[2][3];
			T Coef02 = data[1][2] * data[3][3] - data[3][2] * data[1][3];
			T Coef03 = data[1][2] * data[2][3] - data[2][2] * data[1][3];

			T Coef04 = data[2][1] * data[3][3] - data[3][1] * data[2][3];
			T Coef06 = data[1][1] * data[3][3] - data[3][1] * data[1][3];
			T Coef07 = data[1][1] * data[2][3] - data[2][1] * data[1][3];

			T Coef08 = data[2][1] * data[3][2] - data[3][1] * data[2][2];
			T Coef10 = data[1][1] * data[3][2] - data[3][1] * data[1][2];
			T Coef11 = data[1][1] * data[2][2] - data[2][1] * data[1][2];

			T Coef12 = data[2][0] * data[3][3] - data[3][0] * data[2][3];
			T Coef14 = data[1][0] * data[3][3] - data[3][0] * data[1][3];
			T Coef15 = data[1][0] * data[2][3] - data[2][0] * data[1][3];

			T Coef16 = data[2][0] * data[3][2] - data[3][0] * data[2][2];
			T Coef18 = data[1][0] * data[3][2] - data[3][0] * data[1][2];
			T Coef19 = data[1][0] * data[2][2] - data[2][0] * data[1][2];

			T Coef20 = data[2][0] * data[3][1] - data[3][0] * data[2][1];
			T Coef22 = data[1][0] * data[3][1] - data[3][0] * data[1][1];
			T Coef23 = data[1][0] * data[2][1] - data[2][0] * data[1][1];

			Vector4<T> Fac0(Coef00, Coef00, Coef02, Coef03);
			Vector4<T> Fac1(Coef04, Coef04, Coef06, Coef07);
			Vector4<T> Fac2(Coef08, Coef08, Coef10, Coef11);
			Vector4<T> Fac3(Coef12, Coef12, Coef14, Coef15);
			Vector4<T> Fac4(Coef16, Coef16, Coef18, Coef19);
			Vector4<T> Fac5(Coef20, Coef20, Coef22, Coef23);

			Vector4<T> Vec0(data[1][0], data[0][0], data[0][0], data[0][0]);
			Vector4<T> Vec1(data[1][1], data[0][1], data[0][1], data[0][1]);
			Vector4<T> Vec2(data[1][2], data[0][2], data[0][2], data[0][2]);
			Vector4<T> Vec3(data[1][3], data[0][3], data[0][3], data[0][3]);

			Vector4<T> Inv0(Vec1 * Fac0 - Vec2 * Fac1 + Vec3 * Fac2);
			Vector4<T> Inv1(Vec0 * Fac0 - Vec2 * Fac3 + Vec3 * Fac4);
			Vector4<T> Inv2(Vec0 * Fac1 - Vec1 * Fac3 + Vec3 * Fac5);
			Vector4<T> Inv3(Vec0 * Fac2 - Vec1 * Fac4 + Vec2 * Fac5);

			Vector4<T> SignA(+1, -1, +1, -1);
			Vector4<T> SignB(-1, +1, -1, +1);
			Matrix4x4<T> Inverse;
			Inverse[0] = Inv0 * SignA;
			Inverse[1] = Inv1 * SignB;
			Inverse[2] = Inv2 * SignA;
			Inverse[3] = Inv3 * SignB;

			Vector4<T> Row0(Inverse[0][0], Inverse[1][0], Inverse[2][0], Inverse[3][0]);

			Vector4<T> Dot0(data[0] * Row0);
			T Dot1 = (Dot0.x + Dot0.y) + (Dot0.z + Dot0.w);

			T OneOverDeterminant = 1 / Dot1;

			return Inverse * OneOverDeterminant;
		}
	private:
		Vector4<T> data[4];
	};

	using Float4x4 = Matrix4x4<float>;
	using UInt4x4 = Matrix4x4<int32>;
	using Int4x4 = Matrix4x4<uint32>;
}

namespace std {
	template<typename T>
	inline string to_string(mwengine::Math::Matrix4x4<T>& matrix) {
		stringstream ss;
		
		for (uint8 y = 0; y < 4; y++) {
			ss << "[";

			for (uint8 x = 0; x < 4; x++) {
				ss << to_string(matrix[x][y]);

				if (x != 3) {
					ss << ", ";
				}
			}

			ss << "]";

			if (y != 3) {
				ss << "\n";
			}
		}

		return ss.str();
	}
}