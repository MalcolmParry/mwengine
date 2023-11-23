#include "pch.h"
#include "Vulkan/vkInstance.h"
#include "Vulkan/vkDisplay.h"
#include "Vulkan/vkImage.h"

#define GET_API_CONSTRUCTOR(type, renderApi, ...)					\
	if (renderApi == API_VULKAN)									\
		return (type*) new vk##type##(__VA_ARGS__);					\
	else															\
		MW_ERROR("Render api id: {0} not supported.", renderApi)

using namespace mwengine::RenderAPI::Vulkan;

namespace mwengine::RenderAPI {
	Instance* InternalInstanceCreate(RenderAPI renderApi, Window* window, const std::string& appName, uint32 appVersion, bool debug) {
		GET_API_CONSTRUCTOR(Instance, renderApi, window, appName, appVersion, debug);
	}

	Instance* Instance::Create(RenderAPI renderApi, Window* window, const std::string& appName, uint32 appVersion, bool debug) {
		Instance* instance = InternalInstanceCreate(renderApi, window, appName, appVersion, debug);
		instance->renderApi = renderApi;
		return instance;
	}

	RenderAPI Instance::GetRenderAPI() {
		return renderApi;
	}

	Display* Display::Create(Instance* instance, Window* window) {
		GET_API_CONSTRUCTOR(Display, instance->GetRenderAPI(), instance, window);
	}

	Image* Image::Create(Instance* instance, glm::uvec2 size) {
		GET_API_CONSTRUCTOR(Image, instance->GetRenderAPI(), instance, size);
	}

	Texture* Texture::Create(Instance* instance, Image* image, bool pixelated) {
		GET_API_CONSTRUCTOR(Texture, instance->GetRenderAPI(), instance, image, pixelated);
	}

	Buffer* Buffer::Create(Instance* instance, uint32 size, BufferUsage usage) {
		GET_API_CONSTRUCTOR(Buffer, instance->GetRenderAPI(), instance, size, usage);
	}

	BufferRegion::BufferRegion(Buffer* buffer, uint32 size, uint32 offset) {
		this->buffer = buffer;
		this->size = size;
		this->offset = offset;

		if (buffer != nullptr && size == 0) {
			this->size = buffer->GetSize();
		}
	}

	void BufferRegion::SetData(void* data) {
		buffer->SetData(data, size, offset);
	}

	void BufferRegion::SetData(std::vector<uint8>& data) {
		buffer->SetData(data.data(), data.size(), offset);
	}

	std::vector<uint8>& BufferRegion::GetData() {
		return buffer->GetData(size, offset);
	}
}