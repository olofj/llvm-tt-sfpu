# GCC → Clang Flag Mapping for SFPU Compilation

## Architecture Flags

| GCC Flag | Clang Equivalent | Context |
|----------|-----------------|---------|
| `-mcpu=tt-bh-tensix` | `-march=rv32imac_xttsfpu_xttsfpubh -mabi=ilp32` | BH compute cores |
| `-mcpu=tt-bh` | `-march=rv32imac_zaamo_zba_zbb -mabi=ilp32` | BH non-compute |
| `-mcpu=tt-wh-tensix` | `-march=rv32imac_xttsfpu_xttsfpuwh -mabi=ilp32` | WH compute cores |
| `-mcpu=tt-wh` | `-march=rv32imac -mabi=ilp32` | WH non-compute |

## Compiler Flags

| GCC Flag | Clang Equivalent | Notes |
|----------|-----------------|-------|
| `-std=c++17` | `-std=c++17` | Same |
| `-flto=auto` | `-flto=thin` | Clang uses ThinLTO |
| `-ffast-math` | `-ffast-math` | Same |
| `-fno-exceptions` | `-fno-exceptions` | Same |
| `-fno-use-cxa-atexit` | `-fno-use-cxa-atexit` | Same |
| `-Os` / `-O3` | `-Os` / `-O3` | Same |
| `-MMD` | `-MMD` | Same |
| `-Wall -Werror` | `-Wall -Werror` | Same |
| `-Wno-unknown-pragmas` | `-Wno-unknown-pragmas` | Same |
| `-Wno-error=multistatement-macros` | (not needed) | GCC-specific |
| `-fdump-rtl-all` | (not available) | GCC debug dumps |

## Additional Clang Flags Needed

| Flag | Purpose |
|------|---------|
| `--target=riscv32-unknown-elf` | Cross-compilation target |
| `-include sfpi_compat.h` | Builtin name compatibility |
| `-fno-integrated-as` | Use external assembler (optional) |
| `-mno-relax` | Disable linker relaxation (match GCC) |

## Environment Variable

Set `TT_METAL_USE_LLVM_SFPU=1` to enable LLVM compiler path.
Unset or `=0` to use the default sfpi-gcc.

## Linker

The linker scripts and flags remain the same — clang will invoke the linker
with `-fuse-ld=` pointing to the riscv-tt-elf-ld from the sfpi toolchain,
or use LLVM's lld with `--target=riscv32-unknown-elf`.

## Pre-defined Macros

| GCC | Clang | Notes |
|-----|-------|-------|
| `__riscv_xtttensixwh` | `__SFPU_WH__` (custom) | Set via `-D` |
| `__riscv_xtttensixbh` | `__SFPU_BH__` (custom) | Set via `-D` |
| `__riscv_xlen=32` | `__riscv_xlen=32` | Both set this |
