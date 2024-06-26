#include "pch.h"

#include "Vulkan/vkRenderAPI.h"

#define CALL_API_VULKAN_CONSTRUCTOR(type, ...) return (type*) new vk##type##(__VA_ARGS__)

#define CALL_API_SPECIFIC_CONSTRUCTOR(type, renderApi, ...)			\
	switch (renderApi) {											\
	case mwengine::RenderAPI::API_VULKAN:							\
		CALL_API_VULKAN_CONSTRUCTOR(type, __VA_ARGS__);				\
	default:														\
		MW_ERROR("Render api id: {0} not supported.", renderApi);	\
	}

using namespace mwengine::RenderAPI::Vulkan;

namespace mwengine::RenderAPI {
	Instance* InternalInstanceCreate(RenderAPI renderApi, Window* window, const std::string& appName, uint32 appVersion, bool debug) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Instance, renderApi, window, appName, appVersion, debug);
	}

	Instance* Instance::Create(RenderAPI renderApi, Window* window, const std::string& appName, uint32 appVersion, bool debug) {
		Instance* instance = InternalInstanceCreate(renderApi, window, appName, appVersion, debug);
		instance->renderApi = renderApi;
		return instance;
	}

	RenderAPI Instance::GetRenderAPI() const {
		return renderApi;
	}

	Display* Display::Create(Instance* instance, Window* window) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Display, instance->GetRenderAPI(), instance, window);
	}

	Image* Image::Create(Instance* instance, Math::UInt2 size) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Image, instance->GetRenderAPI(), instance, size);
	}

	Texture* Texture::Create(Instance* instance, Image* image, bool pixelated) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Texture, instance->GetRenderAPI(), instance, image, pixelated);
	}

	Buffer* Buffer::Create(Instance* instance, uint64 size, BufferUsage usage) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Buffer, instance->GetRenderAPI(), instance, size, usage);
	}

	Shader* Shader::Create(Instance* instance, const std::vector<uint8>& code) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Shader, instance->GetRenderAPI(), instance, code);
	}

	Shader* Shader::Create(Instance* instance, const std::string& filepath) {
		std::ifstream file(filepath, std::ios::ate | std::ios::binary);
		if (!file.is_open())
			MW_ERROR("Shader file failed to open.");

		uint32 size = (uint32) file.tellg();
		std::vector<uint8> code(size);
		file.seekg(0);
		file.read((char*) code.data(), size);
		file.close();

		return Create(instance, code);
	}

	GraphicsPipeline* GraphicsPipeline::Create(Instance* instance) {
		CALL_API_SPECIFIC_CONSTRUCTOR(GraphicsPipeline, instance->GetRenderAPI(), instance);
	}

	CommandBuffer* CommandBuffer::Create(Instance* instance) {
		CALL_API_SPECIFIC_CONSTRUCTOR(CommandBuffer, instance->GetRenderAPI(), instance);
	}

	Framebuffer* Framebuffer::Create(Instance* instance, RenderPass* renderPass, Image* image, Image* depthImage) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Framebuffer, instance->GetRenderAPI(), instance, renderPass, image, depthImage);
	}

	ResourceLayout* ResourceLayout::Create(Instance* instance, std::vector<BindingDescriptor> bindingDescriptors) {
		CALL_API_SPECIFIC_CONSTRUCTOR(ResourceLayout, instance->GetRenderAPI(), instance, bindingDescriptors);
	}

	ResourceSet* ResourceSet::Create(ResourceLayout* layout) {
		CALL_API_SPECIFIC_CONSTRUCTOR(ResourceSet, layout->GetInstance()->GetRenderAPI(), layout);
	}

	Semaphore* Semaphore::Create(Instance* instance) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Semaphore, instance->GetRenderAPI(), instance);
	}

	Fence* Fence::Create(Instance* instance, bool enabled) {
		CALL_API_SPECIFIC_CONSTRUCTOR(Fence, instance->GetRenderAPI(), instance, enabled);
	}

	RenderPass* RenderPass::Create(Instance* instance, Display* display) {
		CALL_API_SPECIFIC_CONSTRUCTOR(RenderPass, instance->GetRenderAPI(), instance, display);
	}

	BufferRegion::BufferRegion() {
		this->buffer = nullptr;
		this->size = 0;
		this->offset = 0;
	}

	BufferRegion::BufferRegion(Buffer* buffer, uint64 size, uint64 offset) {
		this->buffer = buffer;
		this->size = size;
		this->offset = offset;

		if (buffer != nullptr && size == 0) {
			this->size = buffer->GetSize();
		}
	}

	BufferRegion::BufferRegion(Buffer* buffer, uint64 size, BufferRegion& offset) {
		this->buffer = buffer;
		this->size = size;
		this->offset = offset.GetChainOffset();
	}

	uint64 BufferRegion::GetChainOffset() {
		return size + offset;
	}

	void BufferRegion::SetData(void* data) {
		buffer->SetData(data, size, offset);
	}

	void BufferRegion::SetData(std::vector<uint8>& data) {
		buffer->SetData(data.data(), data.size(), offset);
	}

	std::vector<uint8> BufferRegion::GetData() {
		return buffer->GetData(size, offset);
	}
}