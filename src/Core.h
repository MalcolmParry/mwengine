#pragma once

#include <cstdint>

typedef int8_t int8;
typedef int16_t int16;
typedef int32_t int32;
typedef int64_t int64;

typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;
typedef uint64_t uint64;

#define MW_BIT(x) (1 << x)

#define MW_MAKE_VERSION(major, minor, patch) ((((uint32)(major)) << 22U) | (((uint32)(minor)) << 12U) | ((uint32)(patch)))
#define MW_GET_VERSION_MAJOR(version) ((uint32)(version) >> 22U)
#define MW_GET_VERSION_MINOR(version) (((uint32)(version) >> 12U) & 0x3FFU)
#define MW_GET_VERSION_PATCH(version) ((uint32)(version) & 0xFFFU)

#define MW_VERSION MW_MAKE_VERSION(0, 0, 1)

#ifdef _WIN64
	#define MW_PLATFORM WINDOWS
#else
	#error No Windows?
#endif