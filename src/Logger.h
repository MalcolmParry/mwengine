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

#if defined(MWENGINE) && defined(MW_NO_LOG)
#define MW_LOG_WRAP(x)
#else
#define MW_LOG_WRAP(x) x
#endif

#define MW_PRINT(...) MW_LOG_WRAP(MW_GET_LOGGER().Print(__VA_ARGS__))
#define MW_LOG(...) MW_LOG_WRAP(MW_GET_LOGGER().Log(__VA_ARGS__))
#define MW_TRACE(...) MW_LOG_WRAP(MW_GET_LOGGER().Trace(__VA_ARGS__))
#define MW_WARN(...) MW_LOG_WRAP(MW_GET_LOGGER().Warn(__VA_ARGS__))
#define MW_ERROR(...) { MW_LOG_WRAP(MW_GET_LOGGER().Error(__VA_ARGS__)); LOGGER_EXIT(""); }
#define MW_ASSERT(condition, ...) if (!(condition)) { MW_ERROR(__VA_ARGS__); }
#define MW_WARN_ASSERT(condition, ...) if (!(condition)) { MW_ASSERT(__VA_ARGS__); }