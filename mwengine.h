/*

Optional defines:
	- MW_NO_LOG = Disables all logging
	- MW_INCLUDE_VULKAN = Includes vulkan headers
	- MW_VECTOR_FORWARD = Sets forward vector
	- MW_VECTOR_UP = Sets up vector
	- MW_VECTOR_RIGHT = Sets right vector

*/

#pragma once

#ifndef _WIN32
#error Only windows is supported.
#endif

#include "src/pch.h"
#include "src/Logger.h"

#include "src/Window.h"
#include "src/Camera.h"
#include "src/Transform.h"

#include "src/RenderAPI/Instance.h"
#include "src/RenderAPI/PhysicalDevice.h"
#include "src/RenderAPI/Display.h"
#include "src/RenderAPI/ImageFormat.h"
#include "src/RenderAPI/Image.h"

#ifdef MW_INCLUDE_VULKAN

#include "src/RenderAPI/Vulkan/vkInstance.h"
#include "src/RenderAPI/Vulkan/vkPhysicalDevice.h"
#include "src/RenderAPI/Vulkan/vkDisplay.h"
#include "src/RenderAPI/Vulkan/vkShader.h"
#include "src/RenderAPI/Vulkan/vkGraphicsPipeline.h"
#include "src/RenderAPI/Vulkan/vkCommandBuffer.h"

#endif