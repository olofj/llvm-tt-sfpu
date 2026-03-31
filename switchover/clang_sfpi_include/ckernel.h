/*
 * ckernel.h wrapper for clang — works around GCC's `uint32_t short` extension
 * used in get_cfg16_pointer(), and fixes const-qualification of MMIO pointers
 * so clang can constant-fold them (matching GCC's behavior with __PTR_CONST).
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
