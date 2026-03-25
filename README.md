# LLVM Backend for Tenstorrent SFPU ISA

LLVM RISC-V vendor extension (`XttSFPU`) implementing the Tenstorrent SFPU
(Scalar/Vector FPU) instruction set for Blackhole (BH) and Wormhole (WH)
Tensix coprocessors.

## Status

**Phase 1**: Feature registration, register classes, instruction encoding (MVP assembler)

## Quick Start

```bash
./scripts/setup.sh    # Clone LLVM, apply patches, configure CMake
./scripts/build.sh    # Build LLVM with SFPU support
./scripts/test.sh     # Run test suite
```

## Architecture

SFPU instructions are Tensix coprocessor instructions injected into the Tensix
instruction FIFO by RISC-V cores via memory-mapped writes. The 32-bit Tensix
instruction word format:

```
[31:24] = Tensix opcode (0x70–0x95)
[23:0]  = Payload (operand fields, varies by encoding family)
```

This backend implements them as a RISC-V vendor extension using LLVM's
`InstFormatOther` with custom bit-field assignments.

## Target Architectures

- **Blackhole** (primary): Hardware scoreboarding, richer ISA
- **Wormhole**: Software NOP insertion, tighter register constraints
- **Quasar** (future): SFPNONLINEAR, DI instructions

## Directory Structure

```
docs/               Design documents and encoding references
llvm-project/       LLVM source tree (sparse checkout, RISCV target only)
patches/            Exportable patch series
sfpu-headers/       SFPI-compatible C++ headers
tests/              LLVM lit tests (encoding, codegen, regression)
scripts/            Build and test automation
```

## Key Files in llvm/lib/Target/RISCV/

| File | Purpose |
|------|---------|
| `RISCVInstrInfoXttSFPU.td` | 38 SFPU instruction definitions, 6 encoding formats |
| `RISCVRegisterInfoXttSFPU.td` | L0-L16 register classes |
| `RISCVSchedXttSFPU.td` | Pipeline model (5 sub-units, latencies) |

## References

- `../ttsim-analysis/ERRATA.md` — Hardware errata (E-001–E-014) and ISA corrections (C-001–C-030)
- `../ttsim-analysis/FUNCTIONAL_UNITS.md` — Sub-unit architecture and encoding formats
- `../ttsim-analysis/ISA_SPEC.md` — Reverse-engineered ISA specification
