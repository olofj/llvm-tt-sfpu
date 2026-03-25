#!/bin/bash
# setup.sh — Clone LLVM, apply XttSFPU patches, configure CMake
#
# Creates a shallow sparse checkout of llvm-project containing only the
# RISC-V target, include files, and CMake infrastructure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LLVM_DIR="$PROJECT_DIR/llvm-project"

LLVM_REPO="https://github.com/llvm/llvm-project.git"
LLVM_BRANCH="main"

echo "=== LLVM XttSFPU Setup ==="

# Step 1: Clone LLVM (shallow sparse checkout)
if [ ! -d "$LLVM_DIR/.git" ] || [ ! -f "$LLVM_DIR/llvm/CMakeLists.txt" ]; then
    echo "Cloning LLVM (shallow sparse checkout)..."

    # Initialize sparse checkout
    if [ ! -d "$LLVM_DIR/.git" ]; then
        mkdir -p "$LLVM_DIR"
        cd "$LLVM_DIR"
        git init
        git remote add origin "$LLVM_REPO"
        git config core.sparseCheckout true

        # Define sparse checkout paths
        cat > .git/info/sparse-checkout << 'EOF'
llvm/CMakeLists.txt
llvm/cmake/
llvm/include/
llvm/lib/Target/RISCV/
llvm/lib/Support/
llvm/lib/MC/
llvm/lib/CodeGen/
llvm/lib/Transforms/
llvm/lib/IR/
llvm/lib/Object/
llvm/lib/TargetParser/
llvm/tools/llvm-mc/
llvm/tools/llc/
llvm/tools/opt/
llvm/utils/TableGen/
llvm/utils/lit/
EOF

        echo "Fetching LLVM (depth=1)..."
        git fetch --depth=1 origin "$LLVM_BRANCH"
        git checkout FETCH_HEAD
    fi
else
    echo "LLVM already checked out at $LLVM_DIR"
fi

# Step 2: Apply patches if they exist
PATCH_DIR="$PROJECT_DIR/patches"
if [ -d "$PATCH_DIR" ] && ls "$PATCH_DIR"/*.patch >/dev/null 2>&1; then
    echo "Applying patches..."
    cd "$LLVM_DIR"
    for patch in "$PATCH_DIR"/*.patch; do
        echo "  Applying $(basename "$patch")..."
        git apply --check "$patch" 2>/dev/null && \
            git apply "$patch" || \
            echo "  (already applied or conflict, skipping)"
    done
fi

# Step 3: Verify our files are in place
echo "Verifying XttSFPU files..."
RISCV_DIR="$LLVM_DIR/llvm/lib/Target/RISCV"

required_files=(
    "RISCVInstrInfoXttSFPU.td"
    "RISCVRegisterInfoXttSFPU.td"
    "RISCVSchedXttSFPU.td"
    "RISCVFeaturesXttSFPU.td"
    "RISCVXttSFPUErrata.cpp"
    "RISCVXttSFPULiveness.cpp"
)

all_present=true
for f in "${required_files[@]}"; do
    if [ -f "$RISCV_DIR/$f" ]; then
        echo "  OK: $f"
    else
        echo "  MISSING: $f"
        all_present=false
    fi
done

if ! $all_present; then
    echo "ERROR: Some XttSFPU files are missing. Check your checkout."
    exit 1
fi

# Step 4: Configure CMake build
BUILD_DIR="$PROJECT_DIR/build"
echo "Configuring CMake build in $BUILD_DIR..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake -G Ninja \
    -DLLVM_ENABLE_PROJECTS="" \
    -DLLVM_TARGETS_TO_BUILD="RISCV" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_INCLUDE_TESTS=ON \
    -DLLVM_BUILD_EXAMPLES=OFF \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_PARALLEL_LINK_JOBS=2 \
    "$LLVM_DIR/llvm"

echo ""
echo "=== Setup Complete ==="
echo "Build directory: $BUILD_DIR"
echo "Next step: ./scripts/build.sh"
