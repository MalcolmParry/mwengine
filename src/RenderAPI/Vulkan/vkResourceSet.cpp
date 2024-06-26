#include "pch.h"

#include "vkResourceSet.h"

namespace mwengine::RenderAPI::Vulkan {
	vkResourceLayout::vkResourceLayout(Instance* instance, std::vector<BindingDescriptor> bindingDescriptors) {
		this->instance = (vkInstance*) instance;
		this->bindingDescriptors = bindingDescriptors;

		std::vector<VkDescriptorSetLayoutBinding> layoutBindings(bindingDescriptors.size());
		poolSizes.resize(bindingDescriptors.size());

		for (uint32 i = 0; i < bindingDescriptors.size(); i++) {
			BindingDescriptor& descriptor = bindingDescriptors[i];

			VkDescriptorSetLayoutBinding layoutBinding {};
			layoutBinding.binding = descriptor.binding;
			layoutBinding.descriptorCount = descriptor.count;
			layoutBinding.stageFlags = GetShaderStageVkEnum(descriptor.stage);
			layoutBinding.pImmutableSamplers = nullptr;

			switch (descriptor.type) {
			case RESOURCE_TYPE_UNIFORM_BUFFER:
				layoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
				break;
			case RESOURCE_TYPE_IMAGE:
				layoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
				break;
			default:
				MW_ERROR("Invalid shader resource type {0}.", descriptor.type);
			}

			VkDescriptorPoolSize poolSize {};
			poolSize.type = layoutBinding.descriptorType;
			poolSize.descriptorCount = descriptor.count;

			layoutBindings[i] = layoutBinding;
			poolSizes[i] = poolSize;
		}

		VkDescriptorSetLayoutCreateInfo descriptorLayoutInfo {};
		descriptorLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
		descriptorLayoutInfo.bindingCount = (uint32) layoutBindings.size();
		descriptorLayoutInfo.pBindings = layoutBindings.data();

		if (vkCreateDescriptorSetLayout(((vkInstance*) instance)->GetNativeDevice(), &descriptorLayoutInfo, nullptr, &descriptorSetLayout) != VK_SUCCESS) {
			MW_ERROR("Failed to create descriptor set layout.");
		}
	}

	vkResourceLayout::~vkResourceLayout() {
		vkDestroyDescriptorSetLayout(instance->GetNativeDevice(), descriptorSetLayout, nullptr);
	}

	Instance* vkResourceLayout::GetInstance() {
		return (Instance*) instance;
	}

	std::vector<BindingDescriptor>& vkResourceLayout::GetDescriptors() {
		return bindingDescriptors;
	}

	std::vector<VkDescriptorPoolSize>& vkResourceLayout::GetNativeDescriptorPoolSizes() {
		return poolSizes;
	}

	VkDescriptorSetLayout vkResourceLayout::GetNativeDescriptorSetLayout() {
		return descriptorSetLayout;
	}

	vkResourceSet::vkResourceSet(ResourceLayout* layout) {
		this->layout = (vkResourceLayout*) layout;
		std::vector<VkDescriptorPoolSize>& poolSizes = ((vkResourceLayout*) layout)->GetNativeDescriptorPoolSizes();

		VkDescriptorSetLayout nativeLayout = ((vkResourceLayout*) layout)->GetNativeDescriptorSetLayout();

		VkDescriptorPoolCreateInfo poolInfo {};
		poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
		poolInfo.poolSizeCount = (uint32) poolSizes.size();
		poolInfo.pPoolSizes = poolSizes.data();
		poolInfo.maxSets = 1;

		if (vkCreateDescriptorPool(((vkInstance*) layout->GetInstance())->GetNativeDevice(), &poolInfo, nullptr, &descriptorPool) != VK_SUCCESS) {
			MW_ERROR("Failed to create descriptor pool.");
		}

		VkDescriptorSetAllocateInfo allocInfo {};
		allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
		allocInfo.descriptorPool = descriptorPool;
		allocInfo.descriptorSetCount = 1;
		allocInfo.pSetLayouts = &nativeLayout;

		if (vkAllocateDescriptorSets(((vkInstance*) layout->GetInstance())->GetNativeDevice(), &allocInfo, &descriptorSet) != VK_SUCCESS) {
			MW_ERROR("Failed to allocate descriptor sets.");
		}
	}
	
	vkResourceSet::~vkResourceSet() {
		vkDestroyDescriptorPool(((vkInstance*) layout->GetInstance())->GetNativeDevice(), descriptorPool, nullptr);
	}

	void vkResourceSet::Write(std::vector<WriteResource> writeResources) {
		std::vector<VkWriteDescriptorSet> descriptorWrites(writeResources.size());
		std::vector<VkDescriptorBufferInfo> bufferInfosAll;
		std::vector<VkDescriptorImageInfo> imageInfosAll;

		for (uint32 i = 0; i < writeResources.size(); i++) {
			WriteResource& writeResource = writeResources[i];

			if (writeResource.binding == UINT32_MAX) {
				writeResource.binding = i;
			}

			VkDescriptorType type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
			VkDescriptorBufferInfo* bufferInfos = nullptr;
			VkDescriptorImageInfo* imageInfos = nullptr;
			uint32 index;

			switch (writeResource.type) {
			case RESOURCE_TYPE_UNIFORM_BUFFER:
				type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
				index = (uint32) bufferInfosAll.size();
				bufferInfosAll.resize(index + writeResource.values.size());
				for (uint32 ii = 0; ii < writeResource.values.size(); ii++) {
					Buffer* buffer = (Buffer*) writeResource.values[ii];

					VkDescriptorBufferInfo bufferInfo {};
					bufferInfo.buffer = ((vkBuffer*) buffer)->GetNativeBuffer();
					bufferInfo.offset = 0;
					bufferInfo.range = buffer->GetSize();

					bufferInfosAll[index + ii] = bufferInfo;
				}
				bufferInfos = &bufferInfosAll[index];

				break;
			case RESOURCE_TYPE_IMAGE:
				type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
				index = (uint32) imageInfosAll.size();
				imageInfosAll.resize(index + writeResource.values.size());
				for (uint32 ii = 0; ii < writeResource.values.size(); ii++) {
					Texture* texture = (Texture*) writeResource.values[ii];

					VkDescriptorImageInfo imageInfo {};
					imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
					imageInfo.imageView = ((vkImage*) texture->GetImage())->GetNativeImageView();
					imageInfo.sampler = ((vkTexture*) texture)->GetNativeSampler();

					imageInfosAll[index + ii] = imageInfo;
				}
				imageInfos = &imageInfosAll[index];

				break;
			default:
				MW_ERROR("Invalid shader resource type enum {0}.", writeResource.type);
			}

			VkWriteDescriptorSet descriptorWrite {};
			descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
			descriptorWrite.dstSet = descriptorSet;
			descriptorWrite.dstBinding = writeResource.binding;
			descriptorWrite.dstArrayElement = 0;
			descriptorWrite.descriptorType = type;
			descriptorWrite.descriptorCount = (uint32) writeResource.values.size();
			descriptorWrite.pBufferInfo = bufferInfos;
			descriptorWrite.pImageInfo = imageInfos;
			descriptorWrite.pTexelBufferView = nullptr;
			descriptorWrites[i] = descriptorWrite;
		}

		vkUpdateDescriptorSets(((vkInstance*) layout->GetInstance())->GetNativeDevice(), descriptorWrites.size(), descriptorWrites.data(), 0, nullptr);
	}

	ResourceLayout* vkResourceSet::GetLayout() {
		return (ResourceLayout*) layout;
	}
	
	Instance* vkResourceSet::GetInstance() {
		return layout->GetInstance();
	}

	VkDescriptorSet vkResourceSet::GetNativeDescriptorSet() {
		return descriptorSet;
	}
}