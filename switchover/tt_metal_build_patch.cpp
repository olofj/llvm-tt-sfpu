// tt_metal_build_patch.cpp
//
// Patch for tt_metal/jit_build/build.cpp to support LLVM/clang as an
// alternative to sfpi-gcc for SFPU kernel compilation.
//
// This file shows the exact changes needed in JitBuildEnv::init().
// Apply with: patch -p1 < switchover/tt_metal_build.patch
//
// The key changes:
// 1. Look for clang in addition to riscv-tt-elf-g++
// 2. Map GCC -mcpu flags to clang -march/-mattr flags
// 3. Add -include sfpi_compat.h for builtin name mapping
// 4. Use clang-compatible warning flags

// ============================================================================
// ORIGINAL (lines 112-130 of build.cpp):
// ============================================================================
#if 0
    const std::array<std::string, 2> sfpi_roots = {this->root_ + "runtime/sfpi", "/opt/tenstorrent/sfpi"};

    bool sfpi_found = false;
    for (unsigned i = 0; i < 2; ++i) {
        auto gxx = sfpi_roots[i] + "/compiler/bin/riscv-tt-elf-g++";
        if (std::filesystem::exists(gxx)) {
            this->gpp_ += gxx + " ";
            this->gpp_include_dir_ = sfpi_roots[i] + "/include";
            log_debug(tt::LogBuildKernels, "Using {} sfpi at {}", i ? "system" : "local", sfpi_roots[i]);
            sfpi_found = true;
            break;
        }
    }
    if (!sfpi_found) {
        TT_THROW("sfpi not found at {} or {}", sfpi_roots[0], sfpi_roots[1]);
    }
#endif

// ============================================================================
// PATCHED VERSION:
// ============================================================================
#if 1
    // Check environment variable to select compiler
    const bool use_llvm = std::getenv("TT_METAL_USE_LLVM_SFPU") != nullptr;

    if (use_llvm) {
        // LLVM/clang path
        const std::array<std::string, 3> llvm_paths = {
            this->root_ + "runtime/llvm-sfpu/bin/clang++",
            "/opt/tenstorrent/llvm-sfpu/bin/clang++",
            "clang++",  // system clang as fallback
        };

        bool found = false;
        for (const auto& clang_path : llvm_paths) {
            if (std::filesystem::exists(clang_path) || clang_path == "clang++") {
                this->gpp_ += clang_path + " ";
                this->gpp_ += "--target=riscv32-unknown-elf ";
                this->gpp_ += "-fno-integrated-as ";  // Use external assembler if needed

                // SFPI compatibility header location
                this->gpp_include_dir_ = this->root_ + "runtime/llvm-sfpu/include";

                log_debug(tt::LogBuildKernels, "Using LLVM sfpu compiler at {}", clang_path);
                found = true;
                break;
            }
        }
        if (!found) {
            TT_THROW("LLVM sfpu compiler not found; set TT_METAL_USE_LLVM_SFPU=0 to use GCC");
        }
    } else {
        // Original GCC path (unchanged)
        const std::array<std::string, 2> sfpi_roots = {this->root_ + "runtime/sfpi", "/opt/tenstorrent/sfpi"};

        bool sfpi_found = false;
        for (unsigned i = 0; i < 2; ++i) {
            auto gxx = sfpi_roots[i] + "/compiler/bin/riscv-tt-elf-g++";
            if (std::filesystem::exists(gxx)) {
                this->gpp_ += gxx + " ";
                this->gpp_include_dir_ = sfpi_roots[i] + "/include";
                log_debug(tt::LogBuildKernels, "Using {} sfpi at {}", i ? "system" : "local", sfpi_roots[i]);
                sfpi_found = true;
                break;
            }
        }
        if (!sfpi_found) {
            TT_THROW("sfpi not found at {} or {}", sfpi_roots[0], sfpi_roots[1]);
        }
    }
#endif

// ============================================================================
// Also patch common_flags in the HAL (bh_hal.cpp, wh_hal.cpp):
// ============================================================================

// ORIGINAL (bh_hal.cpp:182-186):
#if 0
    std::string common_flags(const Params& params) const override {
        std::string cflags = params.core_type == HalProgrammableCoreType::TENSIX &&
                                     params.processor_class == HalProcessorClassType::COMPUTE
                                 ? "-mcpu=tt-bh-tensix "
                                 : "-mcpu=tt-bh ";
#endif

// PATCHED (bh_hal.cpp):
#if 1
    std::string common_flags(const Params& params) const override {
        const bool use_llvm = std::getenv("TT_METAL_USE_LLVM_SFPU") != nullptr;
        std::string cflags;

        if (use_llvm) {
            // LLVM flag mapping
            if (params.core_type == HalProgrammableCoreType::TENSIX &&
                params.processor_class == HalProcessorClassType::COMPUTE) {
                cflags = "-march=rv32imac_xttsfpu_xttsfpu-bh "
                         "-mabi=ilp32 "
                         "-include sfpi_compat.h ";
            } else {
                cflags = "-march=rv32imac_zaamo_zba_zbb "
                         "-mabi=ilp32 ";
            }
        } else {
            // Original GCC flags
            cflags = params.core_type == HalProgrammableCoreType::TENSIX &&
                             params.processor_class == HalProcessorClassType::COMPUTE
                         ? "-mcpu=tt-bh-tensix "
                         : "-mcpu=tt-bh ";
        }
#endif

// PATCHED (wh_hal.cpp) — similar pattern:
#if 1
    // For WH:
    // GCC:  -mcpu=tt-wh-tensix
    // LLVM: -march=rv32imac_xttsfpu_xttsfpu-wh -mabi=ilp32 -include sfpi_compat.h
#endif
