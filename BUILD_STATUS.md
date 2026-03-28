# Build Status — Drop-in Ready for sfpi.h + ckernel.h Kernels

## End-to-End Pipeline

Real sfpi.h C++ kernels compile through clang → assembly → .o → linked ELF:

```
clang++ --target=riscv32-unknown-elf -march=rv32imac_xttsfpu_xttsfpubh \
  -mabi=ilp32 -D__SFPU_BH__ -DARCH_BLACKHOLE \
  -include sfpi_compat.h -I runtime/sfpi/include \
  -isystem <gcc12-cxx> -O2 -std=c++17 -fno-exceptions \
  -Wno-builtin-macro-redefined -Wno-macro-redefined -Wno-unknown-attributes \
  -c kernel.cpp -o kernel.o
```

## Benchmark (6 kernels, BH)

```
GCC:  38 instructions (8 NOPs)
LLVM: 31 instructions (0 NOPs)
→ 18% reduction, 100% NOP elimination (errata-safe)
```

## What's Working

**Frontend:**
- `__xtt_vector` builtin type with Sema implicit conversion (`↔ unsigned int`)
- sfpi.h compiles at -O2 (vFloat, vInt, vUInt, v_if/v_endif, dst_reg)
- 60+ SFPU intrinsics with full custom ISel (W_CHAIN + WO_CHAIN)
- sfpreadlreg/sfpwritelreg, sfpselect2/sfpselect4, ttincrwc, ttreplay

**Optimization (10 passes):**
- MUL+ADD → MAD combining
- Horner → Estrin polynomial restructuring (degree 3-4)
- SFPMULI → SFPMUL register-form substitution on immediate overflow
- _lv instruction substitution with tied operands for predication
- TTI fetch fusion (scalar/SFPU clustering)
- Predication elision for trivial v_if bodies
- LZ+SETCC / EXEXP+SETCC peephole fusion
- REPLAY buffer sequence deduplication
- BH scoreboard errata (E-004a, 10 specific instruction combinations)
- WH pipeline NOP insertion + E-002 SHFLSHR1 workaround

**Scheduling:**
- TensixBH/WHScalarModel with per-instruction latencies
- InstRW mappings for all SFPU instructions
- Post-RA scheduler enabled

**Integration:**
- `TT_METAL_USE_LLVM_SFPU=1` build system patches applied
- WH pipeline: clang → llc → llvm-mc end-to-end
- LTO: smoke test passes (cross-module)
- ELF links with GCC's riscv-tt-elf-ld

## Tests

```
test_compile_kernel.sh bh:    10/10 pass
test_compile_kernel.sh wh:    10/10 pass
compare_gcc_llvm.py:          ALL PASSED (encoding + negative + round-trip)
test_all_kernels.sh:          91/91
Benchmark:                    18% reduction
```

### Kernel Coverage (91/91)

All 91 ckernel_sfpu_*.h kernel headers compile under LLVM/clang.

## Known Remaining Issues

1. **Silicon validation** — no testing on actual BH/WH hardware yet

## Quick Test

```bash
# Toolchain tests (10 tests each: syntax, IR, codegen, encoding)
./switchover/test_compile_kernel.sh bh
./switchover/test_compile_kernel.sh wh

# Cross-validation (encoding, negative tests, GCC comparison)
python3 tests/compare_gcc_llvm.py

# Kernel coverage (87/91 ckernel_sfpu_*.h files)
./tests/test_all_kernels.sh

# Environment variables for non-default paths:
#   LLVM_DIR         — LLVM build bin directory
#   TT_METAL_HOME    — tt-metal source tree
#   SFPI_GCC12_CXX   — GCC 12 C++ stdlib headers
#   SFPI_GCC         — GCC cross-compiler for compare tests
```
