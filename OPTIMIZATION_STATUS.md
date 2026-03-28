# SFPU Optimization Pass Status

## Pipeline Overview

10 optimization passes run in the LLVM backend, split across pre-RA and post-RA:

```
Pre-RA (addMachineSSAOptimization):
  1. RISCVXttSFPUCombine   — MUL+ADD→MAD, LOADI folding
  2. RISCVXttSFPUEstrin    — Horner→Estrin polynomial restructuring
  3. RISCVXttSFPUSynth     — Out-of-range immediate synthesis
  4. RISCVXttSFPULiveness  — CC stack liveness, _lv variant selection

Post-RA (addPreEmitPass2):
  5. RISCVXttSFPUCluster      — TTI fetch fusion (group SFPU instructions)
  6. RISCVXttSFPUConstraints  — WH C-010 dst=src_a verification
  7. RISCVXttSFPUPredElide    — Elide trivial v_if/v_endif regions
  8. RISCVXttSFPUPeephole     — LZ+SETCC fusion, EXEXP+SETCC fusion, self-MOV elimination
  9. RISCVXttSFPUReplay       — REPLAY buffer optimization (32-entry sequence dedup)
 10. RISCVXttSFPUErrata       — Hardware errata workarounds (E-001, E-002, E-004/a, E-005, E-012)
```

## Pass Status

| Pass | Status | BH | WH |
|------|--------|----|----|
| Combine | Active | MUL+ADD→MAD, LOADI+OP→IMM16 | Same |
| Estrin | Active | Degree 3-4 Horner→parallel Estrin | Same |
| Synth | Active | SFPMULI→SFPMUL substitution on overflow | Same |
| Liveness | Active | _lv instruction substitution with tied operands | Same |
| Cluster | Active | Hoists scalar ALU above SFPU clusters for TTI fusion | Same |
| Constraints | N/A on BH | — | Post-RA dst=src_a fixup |
| PredElide | Active | Removes trivial PUSHC/SETCC/POPC when body is safe | Same |
| Peephole | Active | 3 patterns (LZ+CC, EXEXP+CC, self-MOV) | Same |
| Replay | Active | Detects repeated sequences ≥ 4 instructions | Same |
| Errata | Active | E-004a scoreboard NOP (BH), full pipeline NOP (WH) | E-004 NOP + E-002 SHFLSHR1 workaround |

## Scheduling Model

Both BH and WH have full `SchedMachineModel` definitions with `InstRW` mappings:
- Scalar: ALU=1, MUL=2 (stall), DIV=33 (stall), Load=2, Branch=1+5 mispredict
- SFPU: Simple=1, MAD/Swap/LUTFP32=2, Load/Store/Round=1, SHFT2=1(BH)/2(WH)
- Post-RA scheduler enabled (`PostRAScheduler = 1`)

## BH Results

```
GCC:  38 total instructions (8 NOPs)
LLVM: 31 total instructions (0 NOPs)
→ 18% instruction reduction, 100% GCC-style NOP elimination
```

BH has hardware scoreboarding that handles most pipeline hazards. LLVM only
inserts NOPs for the 10 specific E-004a scoreboard errata cases (SFPIADD,
SFPSHFT, SFPCONFIG, SFPAND/SFPOR with USE_VB, SFPSWAP non-SWAP modes,
SFPSHFT2 shuffle/shift modes, SFPLUT, SFPLUTFP32).

## Test Coverage

```
test_compile_kernel.sh bh:    10/10
test_compile_kernel.sh wh:    10/10
compare_gcc_llvm.py:          ALL PASSED (encoding + negative + round-trip)
test_all_kernels.sh:          87/91 (4 inter-layer naming conflicts)
```
