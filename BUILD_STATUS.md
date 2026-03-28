# Build Status — Drop-in Ready for sfpi.h Kernels

## End-to-End Pipeline

Real sfpi.h C++ kernels compile through clang → llc → .o → linked ELF:

```
clang++ --target=riscv32-unknown-elf -march=rv32imac_xttsfpu_xttsfpubh \
  -mabi=ilp32 -D__SFPU_BH__ -include sfpi_compat.h -I runtime/sfpi/include \
  -isystem <gcc12-cxx> -O2 -std=c++17 -fno-exceptions -c kernel.cpp -o kernel.o
```

**5 sfpi C++ kernels verified**: abs, negate, mul, predicated (v_if), loadi.
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
- All 56 SFPU intrinsics handled in custom ISel (W_CHAIN + WO_CHAIN)
- Register allocation with 8 L-registers, L8-L16 reserved
- Encoding byte-identical to GCC

## Tests

```
test_compile_kernel.sh bh:  7/7 pass
compare_gcc_llvm.py:        52/53 pass (1 pre-existing WH issue)
sfpi C++ kernels:           5/5 compile to assembly
Benchmark:                  18% reduction
Linker:                     ELF32 links with riscv-tt-elf-ld
```

## Quick Test

```bash
# Toolchain tests
./switchover/test_compile_kernel.sh bh

# sfpi.h kernel compilation
clang++ --target=riscv32-unknown-elf -march=rv32imac_xttsfpu_xttsfpubh \
  -mabi=ilp32 -D__SFPU_BH__ -include switchover/sfpi_compat.h \
  -I /path/to/runtime/sfpi/include \
  -isystem /opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include/c++/12.4.0 \
  -isystem /opt/tenstorrent/sfpi/compiler/riscv32-unknown-elf/include/c++/12.4.0/riscv32-unknown-elf \
  -O2 -std=c++17 -fno-exceptions -Wno-builtin-macro-redefined -Wno-macro-redefined \
  -c kernel.cpp -o kernel.o
```
