// tt_metal_build_patch.cpp — LLVM/clang SFPU integration documentation
//
// STATUS: PATCHES APPLIED to local tt-metal tree.
//
// Three files modified in tt-metal to support TT_METAL_USE_LLVM_SFPU=1:
//
//   1. tt_metal/jit_build/build.cpp      — compiler selection (clang vs GCC)
//   2. tt_metal/llrt/hal/tt-1xx/blackhole/bh_hal.cpp — BH compiler flags
//   3. tt_metal/llrt/hal/tt-1xx/wormhole/wh_hal.cpp  — WH compiler flags
//
// Runtime directory: tt-metal/runtime/llvm-sfpu/
//   bin/clang++            — symlink to LLVM build
//   include/sfpi_compat.h  — GCC→LLVM builtin mapping header
//
// USAGE:
//   export TT_METAL_USE_LLVM_SFPU=1
//   # tt-metal's JIT build system will use clang instead of GCC for SFPU kernels
//
// ============================================================================
// VERIFIED CLANG COMMAND (BH):
// ============================================================================
//
//   clang++ --target=riscv32-unknown-elf
//           -march=rv32imac_xttsfpu_xttsfpubh
//           -mabi=ilp32
//           -D__SFPU_BH__ -DARCH_BLACKHOLE
//           -include sfpi_compat.h
//           -I <tt-metal>/runtime/sfpi/include
//           -isystem <gcc12-cxx>/include/c++/12.4.0
//           -isystem <gcc12-cxx>/include/c++/12.4.0/riscv32-unknown-elf
//           -isystem <bare-metal-c>/include
//           -O2 -std=c++17 -fno-exceptions -ffast-math
//           -Wno-builtin-macro-redefined -Wno-macro-redefined
//           -Wno-unknown-attributes
//           -c kernel.cpp -o kernel.o
//
// ============================================================================
// FLAG MAPPING SUMMARY
// ============================================================================
//
// GCC Flag                    → LLVM/Clang Equivalent
// -mcpu=tt-bh-tensix          → -march=rv32imac_xttsfpu_xttsfpubh -mabi=ilp32
// -mcpu=tt-wh-tensix          → -march=rv32imac_xttsfpu_xttsfpuwh -mabi=ilp32
// -mcpu=tt-bh                 → -march=rv32imac -mabi=ilp32
// -std=c++17                  → -std=c++17 (same)
// -ffast-math                 → -ffast-math (same)
// -fno-exceptions             → -fno-exceptions (same)
//
// ADDITIONAL LLVM FLAGS:
// --target=riscv32-unknown-elf       (cross-compilation target)
// -include sfpi_compat.h             (GCC→LLVM builtin mapping)
// -D__SFPU_BH__ / -D__SFPU_WH__     (architecture detection)
// -DARCH_BLACKHOLE                   (ckernel.h arch selection)
// -isystem <gcc12-cxx-headers>       (C++ stdlib from GCC 12, not 15)
// -Wno-builtin-macro-redefined       (suppress __has_builtin warning)
// -Wno-macro-redefined               (suppress sfpi_builtins.h warning)
// -Wno-unknown-attributes            (suppress rvtt_l1_ptr/rvtt_reg_ptr)
//
// SYSROOT NOTE:
//   Clang needs GCC 12's C++ stdlib headers. GCC 15's headers use
//   GCC-specific builtins (__remove_reference) that clang doesn't have.
//   Path: /opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include/c++/12.4.0
//
// LINKER (unchanged — same ELF format):
//   riscv-tt-elf-ld or lld produce identical ELF32 executables.
//
// LTO NOTE:
//   Cannot mix GCC and LLVM LTO objects. When TT_METAL_USE_LLVM_SFPU=1,
//   ALL SFPU compilation units must use clang. Non-SFPU units can still
//   use GCC (they don't share LTO across the SFPU boundary).
