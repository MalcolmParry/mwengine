#pragma once

#define LOGGER_EXIT(x) throw std::exception(std::to_string(x).c_str())
#include "vendor/Logger/Logger.h"

namespace mwengine {
	Logger::Profile GetAppLogger();
	Logger::Profile GetCoreLogger();
}

#ifdef MWENGINE

#define MW_GET_LOGGER() mwengine::GetCoreLogger()

#else

#define MW_GET_LOGGER() mwengine::GetAppLogger()

#endif

#ifdef MWENGINE
#ifndef MW_NO_LOG

#define MW_PRINT(...) MW_GET_LOGGER().Print(__VA_ARGS__)
#define MW_LOG(...) MW_GET_LOGGER().Log(__VA_ARGS__)
#define MW_TRACE(...) MW_GET_LOGGER().Trace(__VA_ARGS__)
#define MW_WARN(...) MW_GET_LOGGER().Warn(__VA_ARGS__)
#define MW_ERROR(...) MW_GET_LOGGER().Error(__VA_ARGS__)

#else

#define MW_PRINT(...)
#define MW_LOG(...)
#define MW_TRACE(...)
#define MW_WARN(...)
#define MW_ERROR(...)

#endif
#endif

#define MW_ASSERT(condition, ...) if (!(condition)) { MW_ERROR(__VA_ARGS__); }
#define MW_WARN_ASSERT(condition, ...) if (!(condition)) { MW_ASSERT(__VA_ARGS__); }