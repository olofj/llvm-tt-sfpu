// tt_metal_build_patch.cpp
//
// Patch for tt_metal/jit_build/build.cpp to support LLVM/clang as an
// alternative to sfpi-gcc for SFPU kernel compilation.
//
// The key changes:
// 1. Look for clang in addition to riscv-tt-elf-g++
// 2. Map GCC -mcpu flags to clang -march/-mattr flags
// 3. Add -include sfpi_compat.h for builtin name mapping
// 4. Use clang-compatible warning flags
//
// Enabled by: TT_METAL_USE_LLVM_SFPU=1

// ============================================================================
// PATCH 1: JitBuildEnv::init() — compiler selection
// File: tt_metal/jit_build/build.cpp
// ============================================================================

// After the existing sfpi_roots search, add LLVM path:

#if 0 // CONTEXT: Shows where in build.cpp to apply

    // --- Add this block BEFORE the existing GCC search ---
    const bool use_llvm_sfpu = std::getenv("TT_METAL_USE_LLVM_SFPU") != nullptr;

    if (use_llvm_sfpu) {
        // Search for LLVM clang compiler
        const std::array<std::string, 3> llvm_paths = {
            this->root_ + "runtime/llvm-sfpu/bin/clang++",
            "/opt/tenstorrent/llvm-sfpu/bin/clang++",
            "clang++",  // system PATH fallback
        };

        bool found = false;
        for (const auto& clang_path : llvm_paths) {
            if (clang_path == "clang++" || std::filesystem::exists(clang_path)) {
                this->gpp_ += clang_path + " ";
                this->gpp_ += "--target=riscv32-unknown-elf ";

                // SFPI compatibility header
                this->gpp_include_dir_ = this->root_ + "runtime/llvm-sfpu/include";

                log_debug(tt::LogBuildKernels,
                          "Using LLVM SFPU compiler at {}", clang_path);
                found = true;
                break;
            }
        }
        if (!found) {
            TT_THROW("LLVM sfpu compiler not found; unset TT_METAL_USE_LLVM_SFPU to use GCC");
        }
    } else {
        // --- Original GCC search (unchanged) ---
        // ...existing sfpi_roots code...
    }

#endif

// ============================================================================
// PATCH 2: BH common_flags()
// File: tt_metal/llrt/hal/tt-1xx/blackhole/bh_hal.cpp
// ============================================================================

#if 0 // CONTEXT

    std::string common_flags(const Params& params) const override {
        const bool use_llvm = std::getenv("TT_METAL_USE_LLVM_SFPU") != nullptr;
        std::string cflags;

        if (params.core_type == HalProgrammableCoreType::TENSIX &&
            params.processor_class == HalProcessorClassType::COMPUTE) {
            if (use_llvm) {
                // LLVM: -mcpu=tensix-bh auto-enables xttsfpu+xttsfpubh via ProcessorModel
                cflags = "-mcpu=tensix-bh "
                         "-mabi=ilp32 "
                         "-D__SFPU_BH__ "
                         "-include sfpi_compat.h ";
            } else {
                // GCC (original)
                cflags = "-mcpu=tt-bh-tensix ";
            }
        } else {
            if (use_llvm) {
                cflags = "-march=rv32imac -mabi=ilp32 ";
            } else {
                cflags = "-mcpu=tt-bh ";
            }
        }

#endif

// ============================================================================
// PATCH 3: WH common_flags()
// File: tt_metal/llrt/hal/tt-1xx/wormhole/wh_hal.cpp
// ============================================================================

#if 0 // CONTEXT

    std::string common_flags(const Params& params) const override {
        const bool use_llvm = std::getenv("TT_METAL_USE_LLVM_SFPU") != nullptr;
        std::string cflags;

        if (params.core_type == HalProgrammableCoreType::TENSIX &&
            params.processor_class == HalProcessorClassType::COMPUTE) {
            if (use_llvm) {
                cflags = "-mcpu=tensix-wh "
                         "-mabi=ilp32 "
                         "-D__SFPU_WH__ "
                         "-include sfpi_compat.h ";
            } else {
                cflags = "-mcpu=tt-wh-tensix ";
            }
        } else {
            if (use_llvm) {
                cflags = "-march=rv32imac -mabi=ilp32 ";
            } else {
                cflags = "-mcpu=tt-wh ";
            }
        }

#endif

// ============================================================================
// Flag mapping summary:
//
// GCC -mcpu=tt-bh-tensix  → LLVM -mcpu=tensix-bh -mabi=ilp32 -D__SFPU_BH__
// GCC -mcpu=tt-wh-tensix  → LLVM -mcpu=tensix-wh -mabi=ilp32 -D__SFPU_WH__
// GCC -mcpu=tt-bh         → LLVM -march=rv32imac -mabi=ilp32
// GCC -mcpu=tt-wh         → LLVM -march=rv32imac -mabi=ilp32
//
// The -mcpu=tensix-bh/wh flags auto-enable the correct xttsfpu* features
// via the ProcessorModel definitions in RISCVProcessors.td.
//
// Additional required flags for LLVM:
//   --target=riscv32-unknown-elf    (cross-compilation target)
//   -include sfpi_compat.h          (GCC→LLVM builtin name mapping)
//   -D__SFPU_BH__ / -D__SFPU_WH__  (architecture detection for compat header)
//   -mno-relax                      (optional: disable linker relaxation)
// ============================================================================
