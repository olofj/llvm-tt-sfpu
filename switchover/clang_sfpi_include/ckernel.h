/*
 * ckernel.h wrapper for clang — works around GCC's `uint32_t short` extension
 * used in get_cfg16_pointer().
 */
#ifdef __clang__
#include <cstring>
#include <utility>
#include <cstdint>
#include <limits>
#include <type_traits>
#define short
#include_next "ckernel.h"
#undef short
#else
#include_next "ckernel.h"
#endif
