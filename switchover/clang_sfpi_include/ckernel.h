/*
 * ckernel.h wrapper for clang — works around GCC's `uint32_t short` extension
 * used in get_cfg16_pointer(). We pre-include headers that use `short` normally,
 * then blank it for the rest of ckernel.h where it only appears in the GCC
 * extension context.
 */
#ifdef __clang__
/* Pre-include system/library headers that ckernel.h pulls in, so their
 * include guards fire when ckernel.h includes them again after we
 * blank `short`. */
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
