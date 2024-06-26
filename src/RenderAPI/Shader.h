#pragma once

#include "src/pch.h"
#include "Instance.h"

namespace mwengine::RenderAPI {
	enum ShaderStage : uint8 {
		SHADER_STAGE_VERTEX = MW_BIT(0),
		SHADER_STAGE_FRAGMENT = MW_BIT(1),
		SHADER_STAGE_COUNT = 2,
		SHADER_STAGE_ALL = 0xFF
	};

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
		// Complex
		SHADER_DATA_TYPE_FLOAT_MAT4
	};
}