#pragma once

#include "src/pch.h"
#include "Instance.h"
#include "Shader.h"
#include "Buffer.h"
#include "Image.h"

namespace mwengine::RenderAPI {
	enum ResourceType : uint8 {
		RESOURCE_TYPE_UNIFORM_BUFFER,
		RESOURCE_TYPE_IMAGE
	};

	struct BindingDescriptor {
		ShaderStage stage;
		ResourceType type;
		uint32 binding;
		uint32 count;
	};

	class ResourceLayout {
	public:
		static ResourceLayout* Create(Instance* instance, std::vector<BindingDescriptor> bindingDescriptors);
		virtual ~ResourceLayout() {}

		virtual Instance* GetInstance() = 0;
		virtual std::vector<BindingDescriptor>& GetDescriptors() = 0;
	};

	struct WriteResource {
		inline WriteResource() = default;
		inline WriteResource(std::vector<Buffer*> values, uint32 binding = UINT32_MAX) { type = RESOURCE_TYPE_UNIFORM_BUFFER; this->binding = binding; this->values = *((std::vector<void*>*) &values); }
		inline WriteResource(std::vector<Texture*> values, uint32 binding = UINT32_MAX) { type = RESOURCE_TYPE_IMAGE; this->binding = binding; this->values = *((std::vector<void*>*) &values); }

		ResourceType type;
		uint32 binding;
		std::vector<void*> values;
	};

	class ResourceSet {
	public:
		static ResourceSet* Create(ResourceLayout* layout);
		virtual ~ResourceSet() {}

		virtual void Write(std::vector<WriteResource> writeResources) = 0;

		virtual ResourceLayout* GetLayout() = 0;
		virtual Instance* GetInstance() = 0;
	};
}