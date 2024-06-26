#pragma once

#include "src/pch.h"
#include "../ResourceSet.h"
#include "vkInstance.h"
#include "vkShader.h"
#include "vkImage.h"

namespace mwengine::RenderAPI::Vulkan {
	class vkResourceLayout : ResourceLayout {
	public:
		vkResourceLayout(Instance* instance, std::vector<BindingDescriptor> bindingDescriptors);
		virtual ~vkResourceLayout();

		virtual Instance* GetInstance();
		virtual std::vector<BindingDescriptor>& GetDescriptors();

		std::vector<VkDescriptorPoolSize>& GetNativeDescriptorPoolSizes();
		VkDescriptorSetLayout GetNativeDescriptorSetLayout();
	private:
		vkInstance* instance;
		std::vector<BindingDescriptor> bindingDescriptors;
		std::vector<VkDescriptorPoolSize> poolSizes;
		VkDescriptorSetLayout descriptorSetLayout;
	};

	class vkResourceSet : ResourceSet {
	public:
		vkResourceSet(ResourceLayout* layout);
		virtual ~vkResourceSet();

		virtual void Write(std::vector<WriteResource> writeResources);

		virtual ResourceLayout* GetLayout();
		virtual Instance* GetInstance();

		VkDescriptorSet GetNativeDescriptorSet();
	private:
		vkResourceLayout* layout;

		VkDescriptorPool descriptorPool;
		VkDescriptorSet descriptorSet;
	};
}