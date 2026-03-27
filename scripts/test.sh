#!/bin/bash
# test.sh — Run LLVM lit tests for XttSFPU (BH and WH)
#
# Requires: build.sh to have completed successfully

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
TEST_DIR="$PROJECT_DIR/tests"

if [ ! -x "$BUILD_DIR/bin/llvm-mc" ]; then
    # Also check llvm-project-upstream build
    BUILD_DIR="$PROJECT_DIR/llvm-project-upstream/build"
fi

if [ ! -x "$BUILD_DIR/bin/llvm-mc" ]; then
    echo "llvm-mc not found. Run ./scripts/build.sh first."
    exit 1
fi

PASS=0
FAIL=0
SKIP=0

# Determine flags from filename: *-wh.* or *-wh-* uses WH, else BH
get_flags() {
    local file="$1"
    local base="$(basename "$file")"
    if [[ "$base" == *"-wh."* ]] || [[ "$base" == *"-wh-"* ]] || [[ "$base" == *"_wh."* ]]; then
        echo "+xttsfpu,+xttsfpu-wh"
    else
        echo "+xttsfpu,+xttsfpu-bh"
    fi
}

# Run a test, capturing pass/fail
run_test() {
    local tool="$1"
    local flags="$2"
    local test="$3"
    local base="$(basename "$test")"
    local arch="BH"
    [[ "$flags" == *"-wh"* ]] && arch="WH"

    printf "  %-45s [%s] " "$base" "$arch"
    if "$BUILD_DIR/bin/$tool" \
        -triple riscv32 \
        -mattr="$flags" \
        "$test" -o /dev/null 2>&1; then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL"
        ((FAIL++))
    fi
}

echo "=== Running XttSFPU Tests ==="

# Run encoding tests (llvm-mc)
echo ""
echo "--- Encoding Tests ---"
for test in "$TEST_DIR"/encoding/*.s; do
    [ -f "$test" ] || continue
    flags=$(get_flags "$test")
    # Assembly rejection tests use 'not' prefix
    base="$(basename "$test")"
    if [[ "$base" == *"rejects"* ]]; then
        printf "  %-45s [WH] " "$base"
        if ! "$BUILD_DIR/bin/llvm-mc" \
            -triple riscv32 \
            -mattr="+xttsfpu,+xttsfpu-wh" \
            "$test" -o /dev/null 2>&1; then
            echo "PASS (correctly rejected)"
            ((PASS++))
        else
            echo "FAIL (should have rejected)"
            ((FAIL++))
        fi
    else
        run_test "llvm-mc" "$flags" "$test"
    fi
done

# Run regression tests that are assembly
for test in "$TEST_DIR"/regression/*.s; do
    [ -f "$test" ] || continue
    flags=$(get_flags "$test")
    base="$(basename "$test")"
    if [[ "$base" == *"rejects"* ]]; then
        printf "  %-45s [WH] " "$base"
        if ! "$BUILD_DIR/bin/llvm-mc" \
            -triple riscv32 \
            -mattr="+xttsfpu,+xttsfpu-wh" \
            "$test" -o /dev/null 2>&1; then
            echo "PASS (correctly rejected)"
            ((PASS++))
        else
            echo "FAIL (should have rejected)"
            ((FAIL++))
        fi
    else
        run_test "llvm-mc" "$flags" "$test"
    fi
done

# Run codegen tests (llc)
echo ""
echo "--- Codegen Tests ---"
for test in "$TEST_DIR"/codegen/*.ll; do
    [ -f "$test" ] || continue
    flags=$(get_flags "$test")
    # llc uses -mattr not -mattr= and different flag for triple
    base="$(basename "$test")"
    arch="BH"
    [[ "$flags" == *"-wh"* ]] && arch="WH"
    printf "  %-45s [%s] " "$base" "$arch"
    if "$BUILD_DIR/bin/llc" \
        -mtriple riscv32 \
        -mattr="$flags" \
        "$test" -o /dev/null 2>&1; then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL"
        ((FAIL++))
    fi
done

# Run regression tests (llc) — .ll files only
echo ""
echo "--- Regression Tests ---"
for test in "$TEST_DIR"/regression/*.ll; do
    [ -f "$test" ] || continue
    flags=$(get_flags "$test")
    base="$(basename "$test")"
    arch="BH"
    [[ "$flags" == *"-wh"* ]] && arch="WH"
    printf "  %-45s [%s] " "$base" "$arch"
    if "$BUILD_DIR/bin/llc" \
        -mtriple riscv32 \
        -mattr="$flags" \
        "$test" -o /dev/null 2>&1; then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL"
        ((FAIL++))
    fi
done

echo ""
echo "=== Tests Complete ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
