#!/bin/bash
# test.sh — Run LLVM lit tests for XttSFPU
#
# Requires: build.sh to have completed successfully

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
TEST_DIR="$PROJECT_DIR/tests"

if [ ! -x "$BUILD_DIR/bin/llvm-mc" ]; then
    echo "llvm-mc not found. Run ./scripts/build.sh first."
    exit 1
fi

echo "=== Running XttSFPU Tests ==="

# Run encoding tests (Phase 1)
echo ""
echo "--- Encoding Tests ---"
for test in "$TEST_DIR"/encoding/*.s; do
    if [ -f "$test" ]; then
        echo "  Testing $(basename "$test")..."
        "$BUILD_DIR/bin/llvm-mc" \
            -triple riscv32 \
            -mattr=+xttsfpu,+xttsfpu-bh \
            -filetype=obj \
            "$test" -o /dev/null 2>&1 && echo "    PASS" || echo "    FAIL"
    fi
done

# Run codegen tests (Phase 3+)
echo ""
echo "--- Codegen Tests ---"
for test in "$TEST_DIR"/codegen/*.ll; do
    if [ -f "$test" ]; then
        echo "  Testing $(basename "$test")..."
        "$BUILD_DIR/bin/llc" \
            -mtriple riscv32 \
            -mattr=+xttsfpu,+xttsfpu-bh \
            "$test" -o /dev/null 2>&1 && echo "    PASS" || echo "    FAIL"
    fi
done

# Run regression tests (Phase 6+)
echo ""
echo "--- Regression Tests ---"
for test in "$TEST_DIR"/regression/*.ll; do
    if [ -f "$test" ]; then
        echo "  Testing $(basename "$test")..."
        "$BUILD_DIR/bin/llc" \
            -mtriple riscv32 \
            -mattr=+xttsfpu,+xttsfpu-bh \
            "$test" -o /dev/null 2>&1 && echo "    PASS" || echo "    FAIL"
    fi
done

echo ""
echo "=== Tests Complete ==="
