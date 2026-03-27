# SFPU Optimization Status

## Current State: BH Active, WH Under Development

The LLVM SFPU backend pipeline works end-to-end for **BH** (18% instruction
reduction, 0 NOPs). **WH** support is being built with a comprehensive test
suite and optimization passes.

### Pass status

| Pass | Code | BH Status | WH Status |
|------|------|-----------|-----------|
| **RISCVXttSFPUCombine** | MUL+ADD→MAD, LOADI+MUL→MULI | Active | Needs C-010 constraint verification |
| **RISCVXttSFPUPeephole** | LZ+SETCC fusion, EXEXP+SETCC | Active | Same as BH (shared instructions) |
| **RISCVXttSFPUReplay** | REPLAY buffer optimization | Partial (marker NOPs only) | Same |
| **RISCVXttSFPUSynth** | Out-of-range immediate synthesis | Partial | Same |
| **RISCVXttSFPULiveness** | CC stack liveness, _lv selection | Partial (_lv marker only) | Same |
| **RISCVXttSFPUConstraints** | WH architectural verification | N/A (no constraints on BH) | Post-RA verification only |
| **RISCVXttSFPUErrata** | HW errata workarounds (E-001–012) | Active (NOP-free on BH) | Active (NOP insertion for E-004) |

### BH results (verified)

```
GCC:  38 total instructions (8 NOPs)
LLVM: 31 total instructions (0 NOPs)
→ 18% instruction reduction, 100% NOP elimination
```

### WH projected gains

| Category | Estimated Cycle Reduction | Mechanism |
|---|---|---|
| Delay slot filling | 10-25% | Scheduler interleaves independent work into 2-cycle gaps |
| MUL+ADD→MAD scheduling | 5-15% | Fused MAD + proper cost model evaluation |
| Extraneous MOV elimination | 2-5% | Register coalescing with C-010 tying |
| Better register allocation | 3-8% | LLVM greedy RA with 8-register constraint |
| **Composite (overlapping)** | **15-30%** | **Primarily scheduling-driven** |

### WH test suite (new)

| Category | Test Files | Purpose |
|---|---|---|
| Encoding | `sfpu-load-store-wh.s` | 2-bit addr_mode, 14-bit addr validation |
| Rejection | `wh-rejects-bh-only.s` | SFPMUL24/SFPARECIP/SFPGT/SFPLE rejected on WH |
| NOP correctness | `wh-nop-insertion.ll` | NOP required after dependent 2-cycle instructions |
| Delay slot optimization | `wh-nop-interleaving.ll` | Independent work fills delay slots (no NOP) |
| Constraint | `wh-dst-src-a-constraint.ll` | C-010: dst=src_a on SFPMUL/SFPMAD/SFPADD |
| Codegen | `sfpu-basic-wh.ll`, `sfpu-softmax-kernel-wh.ll`, `sfpu-exp-kernel-wh.ll` | Full kernel compilation on WH |
| Scheduling | `sfpu-scheduling-wh.ll` | TensixWHModel PostRA scheduler verification |
| Predication | `sfpu-predication-wh.ll` | CC stack (v_if/v_else/v_endif) on WH |
| Numerical oracle | `vectors/run_ttsim_compare.py` | GCC vs LLVM bit-identical output via ttsim |
| Trace debugging | `vectors/trace_compare.py` | Instruction-level divergence analysis |
| Cross-validation | `compare_gcc_llvm.py` (WH tests added) | WH encoding + immediate width + BH rejection |

### Infrastructure already in place

- `copyPhysReg` for SFPU registers (SFPMOV_REG, line 542 of RISCVInstrInfo.cpp)
- SFPU register classes (SFPURegs L0-L7, SFPUAllRegs L0-L16, SFPUStoreRegs, SFPUConstRegs)
- WH instruction definitions (SFPLOAD_WH, SFPSTORE_WH, SFPLUT_WH, SFPLOADMACRO_WH)
- WH/BH feature flags and processor definitions (TENSIX_WH, TENSIX_BH)
- Scheduling models (TensixWHModel, TensixBHModel) with correct latencies
- ISel patterns for all 73 intrinsics + BH-specific patterns

### Remaining work

1. **Debug remaining optimization pass crashes** (some passes crash on functions
   without the specific patterns they look for — need early-exit guards)
2. **Tune WH scheduler** — verify PostRA scheduler fills delay slots effectively
3. **REPLAY pass materialization** — convert marker NOPs to actual REPLAY encoding
4. **_lv variant selection** — implement proper mod1 bit setting (MOD1_LV_FLAG=0x8)
5. **E-002 mod1 validation** — verify SHFLSHR1/SHFLROR1 values against C-020 spec
6. **Integration testing** — compile real tt-metal WH kernels through LLVM
