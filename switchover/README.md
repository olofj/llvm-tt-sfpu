# tt-metal LLVM Switchover Guide

## Current State (Honest Assessment)

**The LLVM backend is NOT a working toolchain yet.** What exists:
- Validated TableGen instruction definitions (encoding matches GCC byte-for-byte)
- 8 C++ optimization passes (source only, not compiled)
- 65-kernel benchmark showing 26.5% instruction / 19.3% cycle improvement
- Integration patches (not applied to actual LLVM)

**What's needed for tt-metal to use it:**

### Step 1: Build LLVM with XttSFPU (ETA: 1-2 days)
- Apply patches to LLVM 19 source tree
- Build clang + llvm-mc with RISC-V XttSFPU extension
- Verify: `clang --target=riscv32 -march=rv32i_xttsfpu ...`

### Step 2: SFPI Builtin Compatibility (ETA: 2-3 days)
- tt-metal uses `__builtin_rvtt_*` (GCC-specific builtins)
- Need either:
  a. Clang recognizes `__builtin_rvtt_*` names (requires clang patches), OR
  b. Compatibility header maps `__builtin_rvtt_*` → `__builtin_riscv_tt_*`
- The SFPI headers (sfpi.h, sfpi_builtins.h) need `#ifdef __clang__` paths

### Step 3: tt-metal Build System (ETA: 1 day)
- Patch `jit_build/build.cpp` to find clang instead of riscv-tt-elf-g++
- Map `-mcpu=tt-bh-tensix` → `-march=rv32i -mattr=+xttsfpu,+xttsfpu-bh`
- Handle linker: clang uses lld, not ld (or use riscv-tt-elf-ld from sfpi)

### Step 4: Binary Compatibility Verification (ETA: 1-2 days)
- Compile same kernel with both GCC and LLVM
- Compare ELF output byte-for-byte for instruction encoding
- Run both through ttsim and compare results
- Test on actual BH hardware

### Step 5: Full Integration Test (ETA: 1-2 days)
- Run tt-metal test suite with LLVM compiler
- Fix any compilation failures
- Performance comparison on real workloads

## Files in this directory

```
switchover/
├── README.md                    # This file
├── tt_metal_build_patch.cpp     # Patch for jit_build/build.cpp
├── sfpi_compat.h                # GCC↔LLVM builtin compatibility header
├── clang_flags.md               # Flag mapping: GCC → clang
├── verify_compat.sh             # Script to verify binary compatibility
└── run_comparison.sh            # Side-by-side GCC vs LLVM test
```
