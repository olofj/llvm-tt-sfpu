#!/bin/bash
# test_compile_kernel.sh — Compile SFPU kernel code with LLVM clang
#
# Tests the toolchain by compiling test C files that use SFPU builtins.
# Verifies both the frontend (builtin → IR) and the full pipeline where ISel
# patterns exist.
#
# Usage: ./test_compile_kernel.sh [--arch=bh|wh] [--llvm-dir=<path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LLVM_DIR="${LLVM_DIR:-$PROJECT_DIR/llvm-project-upstream/build/bin}"
ARCH="${1:-bh}"
RESULTS=()
PASS=0
FAIL=0

# Strip --arch= prefix if present
ARCH="${ARCH#--arch=}"

CLANG="$LLVM_DIR/clang"
LLC="$LLVM_DIR/llc"
LLVM_MC="$LLVM_DIR/llvm-mc"

if [ ! -x "$CLANG" ]; then
    echo "ERROR: clang not found at $CLANG"
    echo "  Build with: cd llvm-project-upstream/build && ninja clang"
    exit 1
fi

if [ "$ARCH" = "bh" ]; then
    MARCH="rv32imac_xttsfpu_xttsfpubh"
    MATTR="+xttsfpu,+xttsfpubh"
    DEFINE="-D__SFPU_BH__"
elif [ "$ARCH" = "wh" ]; then
    MARCH="rv32imac_xttsfpu_xttsfpuwh"
    MATTR="+xttsfpu,+xttsfpuwh"
    DEFINE="-D__SFPU_WH__"
else
    echo "ERROR: Unknown arch '$ARCH'. Use 'bh' or 'wh'."
    exit 1
fi

echo "=== SFPU Toolchain Test ($ARCH) ==="
echo "  clang:   $CLANG"
echo "  llc:     $LLC"
echo "  llvm-mc: $LLVM_MC"
echo "  march:   $MARCH"
echo ""

run_test() {
    local name="$1"
    local cmd="$2"
    printf "  %-40s " "$name"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
        # Show error on failure
        eval "$cmd" 2>&1 | tail -3 | sed 's/^/    /'
    fi
}

# ---- Test 1: clang recognizes -march ----
run_test "clang accepts -march=$MARCH" \
    "echo 'int x;' | $CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 -fsyntax-only -x c -"

# ---- Test 2: llvm-mc assembles SFPU instructions ----
run_test "llvm-mc assembles sfpnop" \
    "echo 'sfpnop' | $LLVM_MC -triple riscv32 -mattr=$MATTR -filetype=obj -o /dev/null"

# ---- Test 3: llc compiles with -mcpu=tensix-$ARCH ----
run_test "llc compiles with -mcpu=tensix-$ARCH" \
    "echo 'define i32 @t() { ret i32 0 }' | $LLC -march=riscv32 -mcpu=tensix-$ARCH -o /dev/null"

# ---- Test 4: clang frontend emits SFPU intrinsics ----
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
cat > "$TMPDIR/test_builtins.c" << 'CEOF'
void test_nop(void) { __builtin_riscv_tt_sfpnop(); }
void test_pushc(void) { __builtin_riscv_tt_sfppushc(); }
void test_popc(void) { __builtin_riscv_tt_sfppopc(); }
unsigned int test_mad(unsigned int a, unsigned int b, unsigned int c) {
    return __builtin_riscv_tt_sfpmad(a, b, c, 0);
}
unsigned int test_loadi(void) {
    return __builtin_riscv_tt_sfploadi(0, 0x3F80);
}
CEOF

run_test "clang emits SFPU intrinsic IR" \
    "$CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 $DEFINE -O2 -emit-llvm -S $TMPDIR/test_builtins.c -o $TMPDIR/test.ll && grep -q 'llvm.riscv.tt.sfpmad' $TMPDIR/test.ll"

# ---- Test 5: clang with sfpi_compat.h ----
cat > "$TMPDIR/test_compat.c" << 'CEOF'
#include "sfpi_compat.h"
void test_nop_compat(void) { __builtin_rvtt_sfpnop(); }
void test_pushc_compat(void) { __builtin_rvtt_sfppushc(0); }
void test_compc_compat(void) { __builtin_rvtt_sfpcompc(); }
CEOF

run_test "clang with sfpi_compat.h" \
    "$CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 $DEFINE -O2 -emit-llvm -S -I$SCRIPT_DIR $TMPDIR/test_compat.c -o $TMPDIR/test_compat.ll && grep -q 'llvm.riscv.tt.sfpnop' $TMPDIR/test_compat.ll"

# ---- Test 6: Architecture-specific builtins via compat header ----
if [ "$ARCH" = "bh" ]; then
    cat > "$TMPDIR/test_arch.c" << 'CEOF'
#include "sfpi_compat.h"
unsigned int test_load_bh(void) {
    return __builtin_rvtt_bh_sfpload(0, 0, 1, 0, 0, 0);
}
unsigned int test_mad_bh(unsigned int a, unsigned int b, unsigned int c) {
    return __builtin_rvtt_bh_sfpmad(a, b, c, 0);
}
CEOF
    run_test "BH-specific builtins via compat header" \
        "$CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 $DEFINE -O2 -emit-llvm -S -I$SCRIPT_DIR $TMPDIR/test_arch.c -o $TMPDIR/test_arch.ll && grep -q 'llvm.riscv.tt.sfpload' $TMPDIR/test_arch.ll"
elif [ "$ARCH" = "wh" ]; then
    cat > "$TMPDIR/test_arch.c" << 'CEOF'
#include "sfpi_compat.h"
unsigned int test_cast_wh(unsigned int src) {
    return __builtin_rvtt_wh_sfpcast(src, 0);
}
void test_config_wh(unsigned int src) {
    __builtin_rvtt_wh_sfpconfig_v(src, 0);
}
CEOF
    run_test "WH-specific builtins via compat header" \
        "$CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 $DEFINE -O2 -emit-llvm -S -I$SCRIPT_DIR $TMPDIR/test_arch.c -o $TMPDIR/test_arch.ll && grep -q 'llvm.riscv.tt' $TMPDIR/test_arch.ll"
fi

# ---- Test 7: readlreg/writelreg/select builtins ----
cat > "$TMPDIR/test_lreg.c" << 'CEOF'
#include "sfpi_compat.h"
unsigned int test_readlreg(void) {
    return __builtin_rvtt_sfpreadlreg(10);  /* read L10 (constant 1.0) */
}
void test_writelreg(unsigned int val) {
    __builtin_rvtt_sfpwritelreg(val, 3);  /* write to L3 */
}
CEOF
run_test "readlreg/writelreg builtins" \
    "$CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 $DEFINE -O2 -emit-llvm -S -I$SCRIPT_DIR $TMPDIR/test_lreg.c -o $TMPDIR/test_lreg.ll && grep -q 'llvm.riscv.tt.sfpreadlreg' $TMPDIR/test_lreg.ll"

# ---- Test 8: ttincrwc emits .word ----
cat > "$TMPDIR/test_incrwc.c" << 'CEOF'
#include "sfpi_compat.h"
void test_incrwc(void) {
    __builtin_rvtt_ttincrwc(0, 2, 0, 0);
}
CEOF
run_test "ttincrwc emits .word instruction" \
    "$CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 $DEFINE -O2 -S -I$SCRIPT_DIR $TMPDIR/test_incrwc.c -o $TMPDIR/test_incrwc.s && grep -q '.word' $TMPDIR/test_incrwc.s"

# ---- Test 9: llvm-mc encoding round-trip ----
if [ -d "$PROJECT_DIR/tests/encoding" ]; then
    if [ "$ARCH" = "wh" ] && [ -f "$PROJECT_DIR/tests/encoding/sfpu-wh-opcodes.s" ]; then
        run_test "llvm-mc WH opcodes encoding test" \
            "$LLVM_MC -triple riscv32 -mattr=$MATTR -filetype=obj $PROJECT_DIR/tests/encoding/sfpu-wh-opcodes.s -o /dev/null"
    else
        run_test "llvm-mc all-opcodes encoding test" \
            "$LLVM_MC -triple riscv32 -mattr=$MATTR -filetype=obj $PROJECT_DIR/tests/encoding/sfpu-all-opcodes.s -o /dev/null"
    fi
fi

# ---- Test 10: actual codegen (compile to assembly, verify SFPU instructions) ----
cat > "$TMPDIR/test_codegen.c" << 'CEOF'
#include "sfpi_compat.h"
void test_codegen(void) {
    unsigned int v = __builtin_riscv_tt_sfploadi(0, 0x3F80);
    unsigned int w = __builtin_riscv_tt_sfpmad(v, v, 9, 0);
    __builtin_riscv_tt_sfpstore(w, 0, 7, 0);
}
CEOF
run_test "codegen emits SFPU assembly" \
    "$CLANG --target=riscv32-unknown-elf -march=$MARCH -mabi=ilp32 $DEFINE -O2 -S -I$SCRIPT_DIR $TMPDIR/test_codegen.c -o $TMPDIR/test_codegen.s && grep -q 'sfploadi' $TMPDIR/test_codegen.s && grep -q 'sfpmad' $TMPDIR/test_codegen.s && grep -q 'sfpstore' $TMPDIR/test_codegen.s"

# Cleanup handled by trap

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
