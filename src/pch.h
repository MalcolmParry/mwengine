#pragma once

#include <iostream>
#include <fstream>
#include <memory>
#include <utility>
#include <algorithm>
#include <functional>

#include <optional>
#include <string>
#include <sstream>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <any>
#include <variant>
#include <chrono>
#include <thread>

#include "Core.h"
#include "Logger.h"

#define EXIT(x) __debugbreak()

// math
#define GLM_FORCE_RADIANS
#define GLM_LEFT_HANDED  
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#include "vendor/GLM/glm/glm.hpp"
#include "vendor/GLM/glm/gtc/matrix_transform.hpp"
#include "vendor/GLM/glm/gtx/string_cast.hpp"

#ifndef MW_VECTOR_FORWARD
#define MW_VECTOR_FORWARD glm::vec3(0, 0, -1)
#endif

#ifndef MW_VECTOR_UP
#define MW_VECTOR_UP glm::vec3(0, 1, 0)
#endif

#ifndef MW_VECTOR_RIGHT
#define MW_VECTOR_RIGHT glm::vec3(1, 0, 0)
#endif