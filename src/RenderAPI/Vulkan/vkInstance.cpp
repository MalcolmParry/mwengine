#include "pch.h"
#include "vkInstance.h"
#include "src/Platform/Windows/WindowsVulkan.h"

namespace mwengine::RenderAPI::Vulkan {
	VkResult CreateDebugUtilsMessengerEXT(VkInstance instance, const VkDebugUtilsMessengerCreateInfoEXT* pCreateInfo, const VkAllocationCallbacks* pAllocator, VkDebugUtilsMessengerEXT* pDebugMessenger) {
		auto func = (PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
		if (func != nullptr) {
			return func(instance, pCreateInfo, pAllocator, pDebugMessenger);
		} else {
			return VK_ERROR_EXTENSION_NOT_PRESENT;
		}
	}

	void DestroyDebugUtilsMessengerEXT(VkInstance instance, VkDebugUtilsMessengerEXT debugMessenger, const VkAllocationCallbacks* pAllocator) {
		auto func = (PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
		if (func != nullptr) {
			func(instance, debugMessenger, pAllocator);
		}
	}

	VKAPI_ATTR VkBool32 VKAPI_CALL DebugCallback(
		VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
		VkDebugUtilsMessageTypeFlagsEXT messageType,
		const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
		void* pUserData) {
		if (messageSeverity >= VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
			MW_WARN("Renderer: {0}\n", pCallbackData->pMessage);
		}

		return VK_FALSE;
	}

	bool CheckValidationLayerSupport(std::vector<const char*>& validationLayers) {
		uint32 layerCount;
		vkEnumerateInstanceLayerProperties(&layerCount, nullptr);

		std::vector<VkLayerProperties> availableLayers(layerCount);
		vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.data());

		for (const char* layerName : validationLayers) {
			bool layerFound = false;

			for (const auto& layerProperties : availableLayers) {
				if (strcmp(layerName, layerProperties.layerName) == 0) {
					layerFound = true;
					break;
				}
			}

			if (!layerFound) {
				return false;
			}
		}

		return true;
	}

	vkInstance::vkInstance(Window* window, const std::string& appName, uint32 appVersion, bool debug) {
		this->window = window;

		VkApplicationInfo appInfo {};
		appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
		appInfo.pApplicationName = appName.c_str();
		appInfo.applicationVersion = appVersion;
		appInfo.pEngineName = "mwengine";
		appInfo.engineVersion = MW_VERSION;
		appInfo.apiVersion = VK_API_VERSION_1_0;

		std::vector<const char*> requiredExtentions = GetRequiredExtentions();
		std::vector<const char*> validationLayers = {
			"VK_LAYER_KHRONOS_validation"
		};

		if (debug) {
			if (CheckValidationLayerSupport(validationLayers)) {
				debug = true;
				requiredExtentions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
			} else {
				debug = false;
				MW_WARN("Renderer: Validation layers requested but none available.");
			}
		}

		this->debug = debug;
		this->debugMessenger = nullptr;

		VkInstanceCreateInfo createInfo {};
		createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
		createInfo.pApplicationInfo = &appInfo;
		createInfo.enabledExtensionCount = (uint32) requiredExtentions.size();
		createInfo.ppEnabledExtensionNames = requiredExtentions.data();
		createInfo.enabledLayerCount = (uint32) (debug ? validationLayers.size() : 0);
		createInfo.ppEnabledLayerNames = debug ? validationLayers.data() : nullptr;

		if (vkCreateInstance(&createInfo, nullptr, &instance) != VK_SUCCESS) {
			MW_ERROR("Renderer: Failed to create rendering instance.");
		}

		if (debug) {
			VkDebugUtilsMessengerCreateInfoEXT debugCreateInfo {};
			debugCreateInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
			debugCreateInfo.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
			debugCreateInfo.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
			debugCreateInfo.pfnUserCallback = DebugCallback;
			debugCreateInfo.pUserData = nullptr;

			if (CreateDebugUtilsMessengerEXT(instance, &debugCreateInfo, nullptr, &debugMessenger) != VK_SUCCESS) {
				MW_ERROR("Renderer: Failed to create debug messenger.");
			}
		}

		surface = CreateSurface(window, instance);

		uint32 deviceCount = 0;
		vkEnumeratePhysicalDevices(instance, &deviceCount, nullptr);

		std::vector<VkPhysicalDevice> devicesNative(deviceCount);
		vkEnumeratePhysicalDevices(instance, &deviceCount, devicesNative.data());

		physicalDevices.resize(deviceCount);

		for (uint32 i = 0; i < deviceCount; i++) {
			physicalDevices[i] = new vkPhysicalDevice(devicesNative[i], instance, surface);
		}
	}

	vkInstance::~vkInstance() {
		for (vkPhysicalDevice* physicalDevice : physicalDevices) {
			delete physicalDevice;
		}

		vkDestroySurfaceKHR(instance, surface, nullptr);

		if (debug) {
			DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nullptr);
		}

		vkDestroyInstance(instance, nullptr);
	}

	std::vector<vkPhysicalDevice*> vkInstance::GetPhysicalDevices() {
		return physicalDevices;
	}

	bool CheckDeviceExtensionSupport(vkPhysicalDevice* device) {
		const std::vector<const char*> requiredDeviceExtensions = {
			VK_KHR_SWAPCHAIN_EXTENSION_NAME
		};

		uint32_t extensionCount;
		vkEnumerateDeviceExtensionProperties(device->GetNativePhysicalDevice(), nullptr, &extensionCount, nullptr);

		std::vector<VkExtensionProperties> availableExtensions(extensionCount);
		vkEnumerateDeviceExtensionProperties(device->GetNativePhysicalDevice(), nullptr, &extensionCount, availableExtensions.data());

		for (const char* extName : requiredDeviceExtensions) {
			bool hasExt = false;

			for (const VkExtensionProperties& availableExt : availableExtensions) {
				if (strcmp(extName, availableExt.extensionName)) {
					hasExt = true;
				}
			}

			if (!hasExt) {
				return false;
			}
		}

		return true;
	}

	bool IsPhysicalDeviceSuitible(vkPhysicalDevice* device, VkSurfaceKHR surface) {
		VkPhysicalDeviceFeatures deviceFeatures;
		vkGetPhysicalDeviceFeatures(device->GetNativePhysicalDevice(), &deviceFeatures);

		bool hasQueueFamilies = device->GetGraphicsQueueFamily().has_value() && device->GetPresentQueueFamily().has_value();
		bool hasDeviceExtentions = CheckDeviceExtensionSupport(device);

		return hasQueueFamilies && hasDeviceExtentions && deviceFeatures.geometryShader;
	}

	vkPhysicalDevice* vkInstance::GetOptimalPhysicalDevice() {
		vkPhysicalDevice* bestDevice = nullptr;
		int32 bestScore = -1;
		for (vkPhysicalDevice* device : physicalDevices) {
			VkPhysicalDevice nativeDevice = device->GetNativePhysicalDevice();

			VkPhysicalDeviceProperties deviceProperties;
			VkPhysicalDeviceFeatures deviceFeatures;
			vkGetPhysicalDeviceProperties(nativeDevice, &deviceProperties);
			vkGetPhysicalDeviceFeatures(nativeDevice, &deviceFeatures);

			int32 score = 0;

			if (deviceProperties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
				score += 1000;
			}

			score += deviceProperties.limits.maxImageDimension2D;

			if (!IsPhysicalDeviceSuitible(device, surface)) {
				score = 0;
			}

			if (score > bestScore) {
				bestScore = score;
				bestDevice = device;
			}
		}

		return bestDevice;
	}

	Window* vkInstance::GetWindow() {
		return window;
	}

	VkInstance vkInstance::GetNativeInstance() {
		return instance;
	}

	VkDebugUtilsMessengerEXT vkInstance::GetNativeDebugMessenger() {
		return debugMessenger;
	}

	VkSurfaceKHR vkInstance::GetNativeSurface() {
		return surface;
	}
}