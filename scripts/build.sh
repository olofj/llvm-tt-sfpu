#!/bin/bash
# build.sh — Build LLVM with XttSFPU support
#
# Builds only the tools needed for SFPU development:
#   llvm-mc    — assembler/disassembler (Phase 1)
#   llc        — IR compiler (Phase 3+)
#   opt        — IR optimizer (Phase 6+)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Build directory not found. Run ./scripts/setup.sh first."
    exit 1
fi

JOBS="${1:-$(nproc)}"
echo "Building LLVM with $JOBS parallel jobs..."

cd "$BUILD_DIR"

# Phase 1: Build llvm-mc (assembler/disassembler)
echo "=== Building llvm-mc (assembler) ==="
cmake --build . --target llvm-mc -- -j"$JOBS"

# Phase 1: Build llvm-tblgen (TableGen for instruction definitions)
echo "=== Building llvm-tblgen ==="
cmake --build . --target llvm-tblgen -- -j"$JOBS"

# Phase 2: Build llc (compiler)
echo "=== Building llc (compiler) ==="
cmake --build . --target llc -- -j"$JOBS"

# Phase 3: Build clang (requires LLVM_ENABLE_PROJECTS="clang" in cmake)
echo "=== Building clang ==="
cmake --build . --target clang -- -j"$JOBS"

echo ""
echo "=== Build Complete ==="
echo "Binaries in: $BUILD_DIR/bin/"
echo ""
echo "Test with:"
echo "  $BUILD_DIR/bin/llvm-mc -triple riscv32 -mattr=+xttsfpu,+xttsfpubh ..."
echo "  $BUILD_DIR/bin/clang --target=riscv32-unknown-elf -march=rv32imac_xttsfpu_xttsfpubh -emit-llvm -S test.c"
echo ""
echo "Run test suite:"
echo "  ./switchover/test_compile_kernel.sh bh"
