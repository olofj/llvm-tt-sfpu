// tt_metal_build_patch.cpp — Exact patches for LLVM/clang SFPU integration
//
// Apply these changes to tt-metal's jit_build system to enable
// TT_METAL_USE_LLVM_SFPU=1 for opt-in LLVM compilation of SFPU kernels.
//
// Tested: 5 sfpi.h C++ kernels (abs, negate, mul, predicated, loadi)
// compile end-to-end at -O2 with correct output.
//
// VERIFIED CLANG COMMAND (BH):
//   clang++ --target=riscv32-unknown-elf
//           -march=rv32imac_xttsfpu_xttsfpubh
//           -mabi=ilp32
//           -D__SFPU_BH__
//           -include <path>/sfpi_compat.h
//           -I <tt-metal>/runtime/sfpi/include
//           -isystem <gcc12-sysroot>/include/c++/12.4.0
//           -isystem <gcc12-sysroot>/include/c++/12.4.0/riscv32-unknown-elf
//           -O2 -std=c++17 -fno-exceptions -ffast-math
//           -Wno-builtin-macro-redefined -Wno-macro-redefined
//           -c kernel.cpp -o kernel.o
//
// SYSROOT NOTE:
//   Clang needs GCC 12's C++ stdlib headers (not GCC 15's — those use
//   GCC-specific builtins like __remove_reference that clang doesn't have).
//   Use /opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include/c++/12.4.0
//   or bundle a compatible C++ header set.
//

// ============================================================================
// PATCH 1: JitBuildEnv::init() — compiler selection
// File: tt_metal/jit_build/build.cpp, around line 119
// ============================================================================

#if 0 // CONTEXT: Apply inside JitBuildEnv::init()

    const bool use_llvm_sfpu = std::getenv("TT_METAL_USE_LLVM_SFPU") != nullptr;

    if (use_llvm_sfpu) {
        // LLVM clang compiler path
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

                // C++ stdlib from GCC 12 sysroot (compatible with clang)
                auto gcc12_sysroot = "/opt/tenstorrent/sfpi/compiler/"
                                     "riscv32-unknown-elf/include/c++/12.4.0";
                this->gpp_ += "-isystem " + std::string(gcc12_sysroot) + " ";
                this->gpp_ += "-isystem " + std::string(gcc12_sysroot)
                            + "/riscv32-unknown-elf ";

                // SFPI compatibility header and include overrides
                this->gpp_include_dir_ = this->root_ + "runtime/llvm-sfpu/include";

                log_debug(tt::LogBuildKernels,
                          "Using LLVM SFPU compiler at {}", clang_path);
                found = true;
                break;
            }
        }
        if (!found) {
            TT_THROW("LLVM sfpu compiler not found; "
                     "unset TT_METAL_USE_LLVM_SFPU to use GCC");
        }
    } else {
        // Original GCC path (unchanged)
        // ... existing sfpi_roots search code ...
    }

#endif

// ============================================================================
// PATCH 2: BH common_flags()
// File: tt_metal/llrt/hal/tt-1xx/blackhole/bh_hal.cpp, around line 182
// ============================================================================

#if 0 // CONTEXT: Apply inside common_flags()

    std::string common_flags(const Params& params) const override {
        const bool use_llvm = std::getenv("TT_METAL_USE_LLVM_SFPU") != nullptr;
        std::string cflags;

        if (params.core_type == HalProgrammableCoreType::TENSIX &&
            params.processor_class == HalProcessorClassType::COMPUTE) {
            if (use_llvm) {
                // LLVM/clang flags for SFPU compute cores
                cflags = "-march=rv32imac_xttsfpu_xttsfpubh "
                         "-mabi=ilp32 "
                         "-D__SFPU_BH__ "
                         "-include sfpi_compat.h "
                         "-Wno-builtin-macro-redefined "
                         "-Wno-macro-redefined ";
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

        return cflags;
    }

#endif

// ============================================================================
// PATCH 3: WH common_flags() (same pattern)
// File: tt_metal/llrt/hal/tt-1xx/wormhole/wh_hal.cpp
// ============================================================================

#if 0

    // WH LLVM flags:
    // -march=rv32imac_xttsfpu_xttsfpuwh -mabi=ilp32 -D__SFPU_WH__

#endif

// ============================================================================
// FLAG MAPPING SUMMARY
// ============================================================================
//
// GCC Flag                    → LLVM/Clang Equivalent
// -mcpu=tt-bh-tensix          → -march=rv32imac_xttsfpu_xttsfpubh -mabi=ilp32
// -mcpu=tt-wh-tensix          → -march=rv32imac_xttsfpu_xttsfpuwh -mabi=ilp32
// -mcpu=tt-bh                 → -march=rv32imac -mabi=ilp32
// -std=c++17                  → -std=c++17 (same)
// -flto=auto                  → -flto=thin (LLVM ThinLTO)
// -ffast-math                 → -ffast-math (same)
// -fno-exceptions             → -fno-exceptions (same)
// -Wall -Werror               → -Wall -Werror (same)
//
// ADDITIONAL LLVM FLAGS:
// --target=riscv32-unknown-elf       (cross-compilation target)
// -include sfpi_compat.h             (GCC→LLVM builtin mapping)
// -D__SFPU_BH__ / -D__SFPU_WH__     (architecture detection)
// -isystem <gcc12-cxx-headers>       (C++ stdlib from GCC 12)
// -Wno-builtin-macro-redefined       (suppress __has_builtin warning)
// -Wno-macro-redefined               (suppress sfpi_builtins.h warning)
//
// LINKER (unchanged — same ELF format):
// clang++ --target=riscv32-unknown-elf -T linker_script \
//   -Wl,--just-symbols=weakened_fw kernel.o -o kernel.elf
//
// LTO NOTE:
// Cannot mix GCC and LLVM LTO objects. When TT_METAL_USE_LLVM_SFPU=1,
// ALL SFPU compilation units must use clang. Non-SFPU units can still
// use GCC (they don't use LTO for cross-unit optimization with SFPU code).
