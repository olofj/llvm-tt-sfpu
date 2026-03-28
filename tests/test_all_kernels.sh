#!/bin/bash
# Test all ckernel_sfpu_*.h files for compilation under LLVM/clang.
# Usage: ./tests/test_all_kernels.sh [--verbose]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LLVM="$REPO_DIR/llvm-project-upstream/build/bin"
COMPAT="$REPO_DIR/switchover/sfpi_compat.h"
TT="/proxmox/tt/tt-metal"
SFPI="$TT/runtime/sfpi/include"
GCC12="/opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include/c++/12.4.0"
SYSROOT="/opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include"
KERNEL_DIR="$TT/tt_metal/hw/ckernels/blackhole/metal/llk_api/llk_sfpu"

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

CLANG="$LLVM/clang++"
FLAGS="--target=riscv32-unknown-elf -march=rv32imac_xttsfpu_xttsfpubh \
  -mabi=ilp32 -D__SFPU_BH__ -DTENSIX_FIRMWARE -DLOCAL_MEM_EN=0 -DARCH_BLACKHOLE -DCOMPILE_FOR_TRISC \
  -include $COMPAT \
  -I$TT -I$TT/ttnn -I$TT/ttnn/cpp -I$TT/tt_metal \
  -I$TT/tt_metal/hw/inc -I$TT/tt_metal/hw/inc/internal/tt-1xx/blackhole \
  -I$TT/tt_metal/third_party/tt_llk/common \
  -I$TT/tt_metal/third_party/tt_llk/common/inc \
  -I$TT/tt_metal/third_party/tt_llk/tt_llk_blackhole/common/inc \
  -I$TT/tt_metal/third_party/tt_llk/tt_llk_blackhole/llk_lib \
  -I$TT/tt_metal/hostdevcommon/api -I$TT/tt_metal/api \
  -I$SFPI -I$KERNEL_DIR -I$KERNEL_DIR/.. \
  -I$TT/tt_metal/third_party/tt_llk/tt_llk_blackhole/common/inc/sfpu \
  -isystem $GCC12 -isystem ${GCC12}/riscv32-unknown-elf -isystem $SYSROOT \
  -O2 -std=c++17 -fno-exceptions -ffast-math \
  -Wno-builtin-macro-redefined -Wno-macro-redefined -Wno-unknown-attributes \
  -fsyntax-only"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

passed=0
failed=0
fail_list=""

for kernel in "$KERNEL_DIR"/ckernel_sfpu_*.h; do
    name=$(basename "$kernel" .h)
    short=${name#ckernel_sfpu_}

    # Generate wrapper that includes ckernel.h + sfpi.h + common deps + kernel
    cat > "$TMPDIR/test.cpp" << EOF
#include "ckernel.h"
#include "sfpi.h"
using namespace sfpi;
// Common dependencies used across multiple kernels
#if __has_include("llk_sfpu_types.h")
#include "llk_sfpu_types.h"
#endif
#if __has_include("ckernel_sfpu_recip.h")
#include "ckernel_sfpu_recip.h"
#endif
#if __has_include("ckernel_sfpu_exp.h")
#include "ckernel_sfpu_exp.h"
#endif
#if __has_include("ckernel_sfpu_load_config.h")
#include "ckernel_sfpu_load_config.h"
#endif
#if __has_include("ckernel_sfpu_is_fp16_zero.h")
#include "ckernel_sfpu_is_fp16_zero.h"
#endif
#if __has_include("ckernel_sfpu_rounding_ops.h")
#include "ckernel_sfpu_rounding_ops.h"
#endif
#if __has_include("ckernel_sfpu_log.h")
#include "ckernel_sfpu_log.h"
#endif
#include "${name}.h"
EOF

    printf "  %-45s " "$short"
    err=$($CLANG $FLAGS "$TMPDIR/test.cpp" 2>&1) || true
    if echo "$err" | grep -q "error:"; then
        echo "FAIL"
        failed=$((failed + 1))
        first_error=$(echo "$err" | grep "error:" | head -1)
        fail_list="$fail_list\n  $short: $first_error"
        [ $VERBOSE -eq 1 ] && echo "$err" | grep "error:" | head -3 | sed 's/^/        /'
    else
        echo "PASS"
        passed=$((passed + 1))
    fi
done

echo ""
echo "=== Results: $passed passed, $failed failed out of $((passed + failed)) ==="
if [ $failed -gt 0 ]; then
    echo ""
    echo "Failed kernels:"
    echo -e "$fail_list"
fi
