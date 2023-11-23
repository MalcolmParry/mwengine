#pragma once

#include "src/pch.h"
#include "Instance.h"

namespace mwengine::RenderAPI {
	class Shader {
	public:
		static Shader* Create(Instance* instance, const std::vector<uint8>& code);
		static Shader* Create(Instance* instance, const std::string& filepath);
		virtual ~Shader() {};

		virtual Instance* GetInstance() = 0;
	};

	enum ShaderDataType : uint8 {
		SHADER_DATA_TYPE_UINT8,
		SHADER_DATA_TYPE_UINT16,
		SHADER_DATA_TYPE_UINT32,
		SHADER_DATA_TYPE_UINT_VEC2,
		SHADER_DATA_TYPE_UINT_VEC3,
		SHADER_DATA_TYPE_UINT_VEC4,
		SHADER_DATA_TYPE_INT8,
		SHADER_DATA_TYPE_INT16,
		SHADER_DATA_TYPE_INT32,
		SHADER_DATA_TYPE_INT_VEC2,
		SHADER_DATA_TYPE_INT_VEC3,
		SHADER_DATA_TYPE_INT_VEC4,
		SHADER_DATA_TYPE_FLOAT,
		SHADER_DATA_TYPE_FLOAT_VEC2,
		SHADER_DATA_TYPE_FLOAT_VEC3,
		SHADER_DATA_TYPE_FLOAT_VEC4,
		SHADER_DATA_TYPE_IMAGE_SAMPLER,
		// Complex
		SHADER_DATA_TYPE_FLOAT_MAT4
	};
}