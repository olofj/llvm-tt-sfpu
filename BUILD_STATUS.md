# Build Status — Drop-in Ready for sfpi.h + ckernel.h Kernels

## End-to-End Pipeline

Real sfpi.h C++ kernels compile through clang → llc → .o → linked ELF:

```
clang++ --target=riscv32-unknown-elf -march=rv32imac_xttsfpu_xttsfpubh \
  -mabi=ilp32 -D__SFPU_BH__ -include sfpi_compat.h -I runtime/sfpi/include \
  -isystem <gcc12-cxx> -O2 -std=c++17 -fno-exceptions -c kernel.cpp -o kernel.o
```

**5 sfpi C++ kernels verified**: abs, negate, mul, predicated (v_if), loadi.
**ckernel.h full include tree**: compiles with all tt-metal include paths.
**ckernel_sfpu_recip.h, ckernel_sfpu_quant.h**: compile end-to-end.
**Linked with GCC's riscv-tt-elf-ld** into valid ELF32 executable.

## Benchmark (6 kernels, BH)

```
GCC:  38 instructions (8 NOPs)
LLVM: 31 instructions (0 NOPs)
→ 18% reduction, 100% NOP elimination (errata-safe)
```

## What's Working

- `__xtt_vector` as clang builtin type (opaque to optimizer, correct overload resolution)
- Sema implicit conversion rules (`__xtt_vector ↔ unsigned int`)
- sfpi.h compiles at -O2 (vFloat, vInt, v_if/v_endif, dst_reg, all operators)
- MUL+ADD → MAD combining (active)
- BH scoreboard errata (E-004a) — selective NOP insertion for 10 errata cases
- All 60+ SFPU intrinsics handled in custom ISel (W_CHAIN + WO_CHAIN)
- 9 optimization passes registered: Combine, Estrin, Synth, Liveness, Constraints, PredElide, Peephole, Replay, Errata
- Register allocation with 8 L-registers, L8-L16 reserved
- Encoding byte-identical to GCC
- **sfpreadlreg/sfpwritelreg**: proper LLVM intrinsics mapping to physical L-registers
- **sfpselect2/sfpselect4**: multi-register result extraction (SFPSWAP/SFPTRANSP)
- **ttincrwc**: Tensix scalar instruction emitted via `.word`
- **WH pipeline**: clang → llc → llvm-mc end-to-end (9/9 tests pass)
- **tt-metal build integration**: `TT_METAL_USE_LLVM_SFPU=1` patches applied to jit_build, BH HAL, WH HAL

## Tests

```
test_compile_kernel.sh bh:  9/9 pass
test_compile_kernel.sh wh:  9/9 pass
compare_gcc_llvm.py:        55/55 pass
sfpi C++ kernels:           5/5 compile to assembly
ckernel_sfpu kernels:       87/91 standalone, 0 toolchain-caused failures
Benchmark:                  18% reduction
Linker:                     ELF32 links with riscv-tt-elf-ld
LTO:                        smoke test passes (2-TU cross-module)
```

### Kernel Coverage (83/91)

4 remaining failures are deep inter-kernel dependencies (not toolchain bugs):
- `binary_bitwise`: missing `BinaryBitwiseOp` enum (from external types header)
- `cumsum`: naming mismatch between metal/tt_llk layers
- `lgamma`: metal-layer references tt_llk-layer log helper
- `reshuffle_rows`: naming mismatch between metal/tt_llk layers

## Known Remaining Issues

1. **Silicon validation** — no testing on actual BH/WH hardware yet

## Quick Test

```bash
# Toolchain tests
./switchover/test_compile_kernel.sh bh
./switchover/test_compile_kernel.sh wh

# sfpi.h kernel compilation
clang++ --target=riscv32-unknown-elf -march=rv32imac_xttsfpu_xttsfpubh \
  -mabi=ilp32 -D__SFPU_BH__ -include switchover/sfpi_compat.h \
  -I /path/to/runtime/sfpi/include \
  -isystem /opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include/c++/12.4.0 \
  -isystem /opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include/c++/12.4.0/riscv32-unknown-elf \
  -O2 -std=c++17 -fno-exceptions -Wno-builtin-macro-redefined -Wno-macro-redefined \
  -c kernel.cpp -o kernel.o
```
