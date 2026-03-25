# LLVM XttSFPU Backend Architecture

## Design Decisions

### Why a RISC-V Vendor Extension?

SFPU instructions are not standard RISC-V — they're Tensix coprocessor words
injected into the Tensix instruction FIFO via memory-mapped writes. However,
the sfpi-gcc toolchain already encodes them in RV32 ELF files using the custom
instruction space (bits[1:0]=0b11, bits[31:24]=Tensix opcode). We follow the
same encoding for binary compatibility.

LLVM's RISC-V backend has mature vendor extension support:
- Feature flags gated by `-mattr=+xttsfpu`
- `let Predicates = [HasXttSFPU]` guards all SFPU definitions
- `DecoderNamespace = "XttSFPU"` isolates the disassembler
- Scheduling models are per-processor (`TensixBHModel`, `TensixWHModel`)

### Encoding Format Classes

Six encoding formats, all using `InstFormatOther` to bypass RISC-V R/I/S/B:

| Format | Inst Count | Payload Layout |
|--------|-----------|----------------|
| Standard Unary | 18 | imm12 + lreg_c + lreg_dest + mod1 |
| 3-Operand | 3 | src_a + src_b + src_c + rsv + dest + mod1 |
| Load/Store BH | 4 | lreg + mod0 + addr_mode(3b) + addr(13b) |
| Load/Store WH | 4 | lreg + mod0 + addr_mode(2b) + addr(14b) |
| Immediate-16 | 4 | imm16 + dest + mod1 |
| StochRnd | 1 | rnd_mode + imm8 + src_b + dest + mod1 |

### Register Allocation Strategy

Only 8 registers (L0-L7) are allocatable. This is extremely tight but matches
what GCC uses. Key decisions:

1. **No spilling by default**: SFPU registers live in a coprocessor with no
   general memory path. Spilling would require SFPSTORE→Dst→SFPLOAD with very
   high cost. We set `CopyCost = -1` to strongly discourage it.

2. **L7 reserved for SFPLUTFP32**: The instruction writes L0, L1, L7 as a
   3-register destination encoding. L7 is modeled with implicit defs.

3. **L8-L15 as read-only sources**: The register allocator sees these as
   available for source operands but never assigns them as destinations.

4. **L16 special**: Only writable by SFPLOADMACRO, only readable by SFPSTORE.

### Scheduling Model

The #1 improvement over GCC (addresses GH-Q-006). Two scheduling models:

**TensixBHModel** (Blackhole):
- Hardware scoreboarding — stalls are handled by the hardware
- 2-cycle MAD operations: scheduler interleaves independent work
- No NOP insertion needed (unlike WH)

**TensixWHModel** (Wormhole):
- No hardware scoreboarding — software must insert NOPs (E-004)
- Errata pass (`RISCVXttSFPUErrata.cpp`) handles NOP insertion post-RA
- Conservative 2-cycle latency for SFPSHFT2 (E-002 workaround)

### Predication (CC Stack)

SFPU uses a per-lane condition code stack for SIMT-style divergent execution:

```
v_if(cond)   → SFPPUSHC + SFPSETCC
v_else       → SFPPOPC + SFPCOMPC + SFPPUSHC
v_endif      → SFPPOPC
```

When a register is "live" across a predicated region, the `_lv` (live value)
instruction variant must be used to preserve per-lane values in disabled lanes.
The `RISCVXttSFPULiveness.cpp` pass determines when `_lv` selection is needed.

### Errata Passes

Post-RA MachineFunctionPasses that handle hardware errata:

| Pass | Errata | Effect |
|------|--------|--------|
| `RISCVXttSFPUErrata` | E-001, E-002, E-004, E-005, E-012 | NOP insertion, hazard workarounds |
| `RISCVXttSFPULiveness` | — | CC stack liveness for `_lv` variants |
| `RISCVXttSFPUReplay` | — | REPLAY optimization (Phase 6) |
| `RISCVXttSFPUSynth` | — | Immediate synthesis (Phase 6) |

### Phase Roadmap

1. **Phase 1** (current): Feature + Registers + Encoding → `llvm-mc` assembler
2. **Phase 2**: Scheduling model → MachineScheduler-aware codegen
3. **Phase 3**: Intrinsics + ISel → compile C with SFPU intrinsics
4. **Phase 4**: Errata passes → correct code on real hardware
5. **Phase 5**: CC stack predication → v_if/v_else/v_endif
6. **Phase 6**: Optimizations → REPLAY, immediate synthesis, SFPGT/SFPLE
7. **Phase 7**: WH support → errata E-001/E-002/E-004, operand constraints
8. **Phase 8**: QS support → SFPNONLINEAR, DI instructions
