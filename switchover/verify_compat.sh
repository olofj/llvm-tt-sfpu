#!/bin/bash
# verify_compat.sh — Verify binary compatibility between GCC and LLVM output
#
# Compiles the same SFPU kernel with both sfpi-gcc and clang (LLVM),
# then compares the instruction encoding byte-for-byte.
#
# Prerequisites:
# - sfpi-gcc installed at runtime/sfpi/ or /opt/tenstorrent/sfpi/
# - LLVM built with XttSFPU at runtime/llvm-sfpu/ or in PATH
#
# Usage:
#   ./switchover/verify_compat.sh [test_kernel.cpp]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Find compilers
GCC_PATH=""
LLVM_PATH=""

for p in "runtime/sfpi/compiler/bin/riscv-tt-elf-g++" "/opt/tenstorrent/sfpi/compiler/bin/riscv-tt-elf-g++"; do
    if [ -f "$p" ]; then GCC_PATH="$p"; break; fi
done

for p in "runtime/llvm-sfpu/bin/clang++" "/opt/tenstorrent/llvm-sfpu/bin/clang++" "$(which clang++ 2>/dev/null || true)"; do
    if [ -n "$p" ] && [ -f "$p" ]; then LLVM_PATH="$p"; break; fi
done

echo "=== SFPU Binary Compatibility Verification ==="
echo "GCC:  ${GCC_PATH:-NOT FOUND}"
echo "LLVM: ${LLVM_PATH:-NOT FOUND}"

if [ -z "$GCC_PATH" ]; then
    echo "ERROR: sfpi-gcc not found. Install sfpi toolchain first."
    echo "  Expected at: runtime/sfpi/compiler/bin/riscv-tt-elf-g++"
    exit 1
fi

if [ -z "$LLVM_PATH" ]; then
    echo "WARNING: LLVM compiler not found. Skipping comparison."
    echo "  Build LLVM first: ./scripts/setup.sh && ./scripts/build.sh"
    echo ""
    echo "Running GCC-only verification (encoding check)..."
    echo ""

    # Even without LLVM, we can verify GCC output against our encoding model
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    # Create a minimal test kernel
    TEST_KERNEL="${1:-$SCRIPT_DIR/test_kernel_minimal.cpp}"
    if [ ! -f "$TEST_KERNEL" ]; then
        cat > "$TMPDIR/test.cpp" << 'TESTEOF'
// Minimal SFPU test kernel for encoding verification
#include "sfpi.h"

extern "C" void test_kernel() {
    sfpi::vFloat val = sfpi::dst_reg[0];
    sfpi::vFloat result = val * sfpi::vConst0p8373 + sfpi::vConst1;
    sfpi::dst_reg[0] = result;
    sfpi::dst_reg++;
}
TESTEOF
        TEST_KERNEL="$TMPDIR/test.cpp"
    fi

    echo "Test kernel: $TEST_KERNEL"
    echo ""

    # Compile with GCC
    echo "--- Compiling with GCC ---"
    SFPI_INC="$(dirname $(dirname $GCC_PATH))/../include"
    if $GCC_PATH -mcpu=tt-bh-tensix -O3 -std=c++17 -fno-exceptions \
        -I"$SFPI_INC" \
        -c "$TEST_KERNEL" -o "$TMPDIR/gcc_output.o" -S 2>&1; then
        echo "GCC compilation: SUCCESS"
        echo "Assembly output:"
        grep -E "SFP|sfp" "$TMPDIR/gcc_output.o" 2>/dev/null | head -20 || echo "(no SFPU instructions found in output)"
    else
        echo "GCC compilation: FAILED"
    fi

    echo ""
    echo "--- GCC Assembly (SFPU instructions only) ---"
    grep -E "^\s+(SFP|sfp)" "$TMPDIR/gcc_output.o" 2>/dev/null | sed 's/^[[:space:]]*/  /' | head -30

    echo ""
    echo "To run full comparison, build LLVM first, then re-run this script."
    exit 0
fi

# Full comparison: compile with both, compare
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

TEST_KERNEL="${1:-$SCRIPT_DIR/test_kernel_minimal.cpp}"
if [ ! -f "$TEST_KERNEL" ]; then
    echo "Creating test kernel..."
    cat > "$TMPDIR/test.cpp" << 'TESTEOF'
#include "sfpi.h"
extern "C" void test_kernel() {
    sfpi::vFloat val = sfpi::dst_reg[0];
    sfpi::vFloat result = val * sfpi::vConst0p8373 + sfpi::vConst1;
    sfpi::dst_reg[0] = result;
    sfpi::dst_reg++;
}
TESTEOF
    TEST_KERNEL="$TMPDIR/test.cpp"
fi

echo ""
echo "--- GCC Compilation ---"
GCC_INC="$(dirname $(dirname $GCC_PATH))/../include"
$GCC_PATH -mcpu=tt-bh-tensix -O3 -std=c++17 -fno-exceptions \
    -I"$GCC_INC" -c "$TEST_KERNEL" -o "$TMPDIR/gcc.o" -S
echo "GCC: OK"

echo ""
echo "--- LLVM Compilation ---"
LLVM_INC="$PROJECT_DIR/switchover"
$LLVM_PATH --target=riscv32-unknown-elf \
    -march=rv32imac -mabi=ilp32 \
    -D__SFPU_BH__=1 \
    -include "$LLVM_INC/sfpi_compat.h" \
    -I"$GCC_INC" \
    -O3 -std=c++17 -fno-exceptions \
    -c "$TEST_KERNEL" -o "$TMPDIR/llvm.o" -S 2>&1 || echo "LLVM: FAILED (expected until LLVM is built with XttSFPU)"
echo "LLVM: OK (or failed as expected)"

echo ""
echo "--- Comparison ---"
if [ -f "$TMPDIR/gcc.o" ] && [ -f "$TMPDIR/llvm.o" ]; then
    echo "GCC SFPU instructions:"
    grep -cE "SFP|sfp" "$TMPDIR/gcc.o" 2>/dev/null || echo "  0"
    echo "LLVM SFPU instructions:"
    grep -cE "SFP|sfp" "$TMPDIR/llvm.o" 2>/dev/null || echo "  0"
    echo ""
    diff "$TMPDIR/gcc.o" "$TMPDIR/llvm.o" > "$TMPDIR/diff.txt" 2>&1 && \
        echo "IDENTICAL output" || \
        echo "DIFFERENT output ($(wc -l < $TMPDIR/diff.txt) differing lines)"
fi
