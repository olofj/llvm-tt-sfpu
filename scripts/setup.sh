#!/bin/bash
# setup.sh — Clone LLVM, integrate XttSFPU files, configure CMake
#
# Creates a shallow sparse checkout of llvm-project containing only
# the RISC-V target and essential build infrastructure, then copies
# our XttSFPU files into the right locations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LLVM_DIR="$PROJECT_DIR/llvm-project"
RISCV_DIR="$LLVM_DIR/llvm/lib/Target/RISCV"

LLVM_REPO="https://github.com/llvm/llvm-project.git"
LLVM_TAG="llvmorg-19.1.0"  # Stable release for reproducibility

echo "=== LLVM XttSFPU Setup ==="
echo "Project: $PROJECT_DIR"
echo "LLVM:    $LLVM_DIR"

# ---- Step 1: Clone LLVM (shallow, full tree needed for build) ----
if [ ! -f "$LLVM_DIR/llvm/CMakeLists.txt" ]; then
    echo ""
    echo "Step 1: Cloning LLVM $LLVM_TAG (shallow)..."
    echo "  This downloads ~200MB and takes 2-5 minutes."

    if [ -d "$LLVM_DIR/.git" ]; then
        echo "  Git repo exists but CMakeLists.txt missing, re-fetching..."
        cd "$LLVM_DIR"
        git fetch --depth=1 origin tag "$LLVM_TAG"
        git checkout FETCH_HEAD
    else
        git clone --depth=1 --branch "$LLVM_TAG" "$LLVM_REPO" "$LLVM_DIR"
    fi
    echo "  Done."
else
    echo "Step 1: LLVM already present, skipping clone."
fi

# ---- Step 2: Copy XttSFPU files into LLVM tree ----
echo ""
echo "Step 2: Integrating XttSFPU files..."

# TableGen files → llvm/lib/Target/RISCV/
for f in RISCVInstrInfoXttSFPU.td RISCVRegisterInfoXttSFPU.td \
         RISCVSchedXttSFPU.td RISCVFeaturesXttSFPU.td \
         RISCVXttSFPUISelPatterns.td; do
    src="$RISCV_DIR/$f"
    if [ -f "$src" ]; then
        echo "  Already in place: $f"
    else
        echo "  Copying: $f"
        cp "$PROJECT_DIR/llvm-project/llvm/lib/Target/RISCV/$f" "$RISCV_DIR/$f"
    fi
done

# C++ passes → llvm/lib/Target/RISCV/
for f in RISCVXttSFPUErrata.cpp RISCVXttSFPULiveness.cpp \
         RISCVXttSFPUReplay.cpp RISCVXttSFPUSynth.cpp \
         RISCVXttSFPUConstraints.cpp RISCVXttSFPUCombine.cpp; do
    src="$RISCV_DIR/$f"
    if [ -f "$src" ]; then
        echo "  Already in place: $f"
    else
        echo "  Copying: $f"
        cp "$PROJECT_DIR/llvm-project/llvm/lib/Target/RISCV/$f" "$RISCV_DIR/$f"
    fi
done

# Intrinsics → llvm/include/llvm/IR/
INTRINSICS_DIR="$LLVM_DIR/llvm/include/llvm/IR"
if [ ! -f "$INTRINSICS_DIR/IntrinsicsRISCVXttSFPU.td" ]; then
    echo "  Copying: IntrinsicsRISCVXttSFPU.td"
    cp "$PROJECT_DIR/llvm-project/llvm/include/llvm/IR/IntrinsicsRISCVXttSFPU.td" \
       "$INTRINSICS_DIR/IntrinsicsRISCVXttSFPU.td"
else
    echo "  Already in place: IntrinsicsRISCVXttSFPU.td"
fi

# ---- Step 3: Patch upstream LLVM files to include our extensions ----
echo ""
echo "Step 3: Patching upstream LLVM files..."

# Add include to RISCVFeatures.td
FEATURES_FILE="$RISCV_DIR/RISCVFeatures.td"
if ! grep -q "RISCVFeaturesXttSFPU" "$FEATURES_FILE" 2>/dev/null; then
    echo "  Patching: RISCVFeatures.td"
    echo '' >> "$FEATURES_FILE"
    echo '// Tenstorrent SFPU Vector Unit' >> "$FEATURES_FILE"
    echo 'include "RISCVFeaturesXttSFPU.td"' >> "$FEATURES_FILE"
else
    echo "  Already patched: RISCVFeatures.td"
fi

# Add include to RISCVInstrInfo.td
INSTRINFO_FILE="$RISCV_DIR/RISCVInstrInfo.td"
if ! grep -q "RISCVInstrInfoXttSFPU" "$INSTRINFO_FILE" 2>/dev/null; then
    echo "  Patching: RISCVInstrInfo.td"
    echo '' >> "$INSTRINFO_FILE"
    echo '// Tenstorrent SFPU instructions' >> "$INSTRINFO_FILE"
    echo 'include "RISCVInstrInfoXttSFPU.td"' >> "$INSTRINFO_FILE"
    echo 'include "RISCVXttSFPUISelPatterns.td"' >> "$INSTRINFO_FILE"
else
    echo "  Already patched: RISCVInstrInfo.td"
fi

# Add include to RISCVRegisterInfo.td
REGINFO_FILE="$RISCV_DIR/RISCVRegisterInfo.td"
if ! grep -q "RISCVRegisterInfoXttSFPU" "$REGINFO_FILE" 2>/dev/null; then
    echo "  Patching: RISCVRegisterInfo.td"
    echo '' >> "$REGINFO_FILE"
    echo '// Tenstorrent SFPU LReg register file' >> "$REGINFO_FILE"
    echo 'include "RISCVRegisterInfoXttSFPU.td"' >> "$REGINFO_FILE"
else
    echo "  Already patched: RISCVRegisterInfo.td"
fi

# Add scheduling model include
SCHED_FILE="$RISCV_DIR/RISCVSchedule.td"
if [ -f "$SCHED_FILE" ] && ! grep -q "RISCVSchedXttSFPU" "$SCHED_FILE" 2>/dev/null; then
    echo "  Patching: RISCVSchedule.td"
    echo '' >> "$SCHED_FILE"
    echo '// Tenstorrent SFPU scheduling model' >> "$SCHED_FILE"
    echo 'include "RISCVSchedXttSFPU.td"' >> "$SCHED_FILE"
else
    echo "  Already patched or not found: RISCVSchedule.td"
fi

# Add intrinsics include
INTRINSICS_RISCV="$INTRINSICS_DIR/IntrinsicsRISCV.td"
if [ -f "$INTRINSICS_RISCV" ] && ! grep -q "IntrinsicsRISCVXttSFPU" "$INTRINSICS_RISCV" 2>/dev/null; then
    echo "  Patching: IntrinsicsRISCV.td"
    echo '' >> "$INTRINSICS_RISCV"
    echo '// Tenstorrent SFPU intrinsics' >> "$INTRINSICS_RISCV"
    echo 'include "IntrinsicsRISCVXttSFPU.td"' >> "$INTRINSICS_RISCV"
else
    echo "  Already patched or not found: IntrinsicsRISCV.td"
fi

# Add C++ passes to CMakeLists.txt
CMAKE_FILE="$RISCV_DIR/CMakeLists.txt"
if [ -f "$CMAKE_FILE" ] && ! grep -q "RISCVXttSFPU" "$CMAKE_FILE" 2>/dev/null; then
    echo "  Patching: CMakeLists.txt (adding .cpp files)"
    # Find the line with the last .cpp file and add ours after
    sed -i '/^  RISCV.*\.cpp$/!b;:a;n;/^  RISCV.*\.cpp$/ba;i\  RISCVXttSFPUCombine.cpp\n  RISCVXttSFPUConstraints.cpp\n  RISCVXttSFPUErrata.cpp\n  RISCVXttSFPULiveness.cpp\n  RISCVXttSFPUReplay.cpp\n  RISCVXttSFPUSynth.cpp' "$CMAKE_FILE" 2>/dev/null || \
        echo "    WARNING: Could not auto-patch CMakeLists.txt, manual edit needed"
else
    echo "  Already patched or not found: CMakeLists.txt"
fi

# Add subtarget bools to RISCVSubtarget.h
SUBTARGET_FILE="$RISCV_DIR/RISCVSubtarget.h"
if [ -f "$SUBTARGET_FILE" ] && ! grep -q "HasXttSFPU" "$SUBTARGET_FILE" 2>/dev/null; then
    echo "  NOTE: RISCVSubtarget.h needs manual editing to add:"
    echo "    bool HasXttSFPU = false;"
    echo "    bool HasXttSFPUBH = false;"
    echo "    bool HasXttSFPUWH = false;"
    echo "    bool hasXttSFPU() const { return HasXttSFPU; }"
    echo "    bool hasXttSFPUBH() const { return HasXttSFPUBH; }"
    echo "    bool hasXttSFPUWH() const { return HasXttSFPUWH; }"
else
    echo "  Already patched: RISCVSubtarget.h"
fi

# ---- Step 4: Configure CMake ----
BUILD_DIR="$PROJECT_DIR/build"
echo ""
echo "Step 4: Configuring CMake..."
echo "  Build directory: $BUILD_DIR"

if command -v ninja &>/dev/null; then
    GENERATOR="-G Ninja"
    echo "  Generator: Ninja"
else
    GENERATOR=""
    echo "  Generator: Make (install ninja for faster builds)"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake $GENERATOR \
    -DLLVM_ENABLE_PROJECTS="" \
    -DLLVM_TARGETS_TO_BUILD="RISCV" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_INCLUDE_TESTS=ON \
    -DLLVM_BUILD_EXAMPLES=OFF \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_PARALLEL_LINK_JOBS=2 \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    "$LLVM_DIR/llvm" 2>&1 | tail -5

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Fix any manual patches noted above"
echo "  2. Run: ./scripts/build.sh"
echo "  3. Run: ./scripts/test.sh"
echo ""
echo "Quick build (just llvm-mc for assembler testing):"
echo "  cd $BUILD_DIR && cmake --build . --target llvm-mc -- -j\$(nproc)"
