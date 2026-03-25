# LLVM XttSFPU vs sfpi-gcc: Codegen Comparison

Analysis of where the LLVM backend matches, beats, or trails GCC.
Based on reading GCC sources: rvtt-insn.def, rvtt-bh.md, rvtt-peephole.md,
gimple-rvtt-combine.cc, rtl-rvtt-schedule.cc, and all 19 custom passes.

## GCC Custom Passes (19 total)

| # | Pass | Type | LLVM Equivalent | Status |
|---|------|------|-----------------|--------|
| 1 | gimple-rvtt-attrib | GIMPLE | Built-in attributes | N/A |
| 2 | gimple-rvtt-cc | GIMPLE | RISCVXttSFPULiveness | Done |
| 3 | gimple-rvtt-combine | GIMPLE | ISel patterns + DAGCombiner | Partial |
| 4 | gimple-rvtt-expand | GIMPLE | ISel lowering | Planned |
| 5 | gimple-rvtt-live | GIMPLE | RISCVXttSFPULiveness | Done |
| 6 | gimple-rvtt-move | GIMPLE | Register allocator | Built-in |
| 7 | gimple-rvtt-synth-expand | GIMPLE | RISCVXttSFPUSynth | Done |
| 8 | gimple-rvtt-synth-nullify | GIMPLE | RISCVXttSFPUSynth | Done |
| 9 | gimple-rvtt-synth-renumber | GIMPLE | RISCVXttSFPUSynth | Done |
| 10 | gimple-rvtt-synth-split | GIMPLE | RISCVXttSFPUSynth | Done |
| 11 | gimple-rvtt-unspec-prop | GIMPLE | N/A (LLVM handles natively) | N/A |
| 12 | gimple-rvtt-warn | GIMPLE | Diagnostics | Planned |
| 13 | rtl-rvtt-fix-wh | RTL | RISCVXttSFPUErrata (E-001) | Done |
| 14 | rtl-rvtt-hll | RTL | RISCVXttSFPUErrata (E-003) | Partial |
| 15 | rtl-rvtt-liveness | RTL | RISCVXttSFPULiveness | Done |
| 16 | rtl-rvtt-peephole | RTL | TableGen patterns | Partial |
| 17 | rtl-rvtt-replay | RTL | RISCVXttSFPUReplay | Done |
| 18 | rtl-rvtt-schedule | RTL | TensixBHModel/TensixWHModel | Done (better) |
| 19 | rtl-rvtt-synth-opcode | RTL | RISCVXttSFPUSynth | Done |

## Where LLVM Beats GCC

### 1. Pipeline Model (GH-Q-006) — THE #1 improvement
GCC: No pipeline model. NOP insertion is a separate pass that only handles
RAW hazards — it cannot interleave independent instructions to fill latency
slots.

LLVM: Full scheduling model (TensixBHModel) with per-instruction latencies,
resource constraints, and the MachineScheduler. Can reorder instructions to
hide 2-cycle MAD latencies by interleaving independent work.

**Expected improvement**: 10-30% fewer cycles on MAD-heavy kernels.

### 2. BH No-NOP Codegen (GH-CC-008)
GCC: Inserts NOPs after 2-cycle instructions even on BH (which has hardware
scoreboarding) because the schedule pass uses "dynamic" delay for MAD/MUL/ADD
on BH — it checks dependency but still adds NOPs when dependent.

LLVM: TensixBHModel knows BH has scoreboarding. For "dynamic" delay
instructions, the errata pass does nothing on BH — the scheduler just models
the latency, and the hardware handles stalls.

**Expected improvement**: Eliminates unnecessary NOPs, ~5% code size reduction.

### 3. SFPGT/SFPLE Direct Use (GH-Q-005)
GCC: Does not generate SFPGT/SFPLE despite BH having them (tt-metal #27337).
Instead generates the old WH sequence: SFPMAD + 2x SFPSETCC.

LLVM: Has SFPGT/SFPLE instruction definitions with ISel patterns. When
targeting BH, comparisons lower directly to the dedicated instructions.

**Expected improvement**: 3 instructions → 1 instruction per comparison.

### 4. Register Allocation
GCC: Uses a fragile data-dependency model (sfpxcondi/sfpassign_lv/sfpnovalue)
to communicate liveness to the register allocator. This is the root of the
"v_if/v_else/v_endif" complexity (GH-A-002).

LLVM: Uses standard SSA + register coalescing with _lv variants tied via
$dest = $live_val constraints. The RA naturally handles register pressure
within the 8-register file.

## Where LLVM Matches GCC

### 1. Immediate Synthesis
Both expand out-of-range immediates to SFPLOADI + register-form sequences.
Field widths: 12-bit (unary), 16-bit (imm16), 13/14-bit (load/store addr).

### 2. CC Stack Liveness
Both track CC stack depth and select _lv variants when a register is live
across a predicated boundary. GCC uses gimple-rvtt-cc + gimple-rvtt-live;
LLVM uses RISCVXttSFPULiveness.

### 3. Errata Workarounds
Both handle E-001 (WH RAW), E-002 (SHFT2 zero-fill), E-004 (NOP insertion),
E-005 (store register restriction), E-012 (ebreak NOPs).

## Where GCC Currently Leads

### 1. SFPLOADI Combining (gimple-rvtt-combine)
GCC folds SFPLOADI + consuming instruction into the immediate form when the
constant fits. Example: `SFPLOADI L3, 0x3F80 + SFPMULI L3` → `SFPMULI 0x3F80`.
LLVM does not yet have this DAGCombiner pattern.

### 2. Negated Operand Folding (gimple-rvtt-combine)
GCC folds `a * (-b)` by toggling the sign bit in the mod field, avoiding a
separate SFPSETSGN instruction. LLVM does not yet pattern-match this.

### 3. REPLAY Optimization (rtl-rvtt-replay)
GCC identifies repeating instruction sequences and replaces clones with REPLAY
instructions. LLVM's RISCVXttSFPUReplay identifies candidates but does not yet
emit REPLAY instructions (Phase 6 TODO).

### 4. HLL Mitigation (rtl-rvtt-hll, E-003)
GCC has a sophisticated high-latency load tracking pass. LLVM's errata pass
handles E-003 but does not yet do cross-BB load latency tracking.

## GCC Codegen Patterns to Match

### Pattern 1: MUL+ADD → MAD (GH-Q-002)
```
; GCC generates:
sfpmul l0, l1, l2, l9, 0     ; 2 cycles
sfpnop                        ; NOP for WH
sfpadd l0, l10, l0, l3, 0    ; 2 cycles
; Should be:
sfpmad l0, l1, l2, l3, 0     ; 2 cycles (single instruction)
```

### Pattern 2: LZ + SETCC Fusion (rvtt-peephole.md)
```
; GCC peephole fuses:
sfplz l0, l1, 0, 0           ; leading zeros
sfpsetcc l0, l1, 0, 2        ; set CC from result
; Into:
sfplz l0, l1, 0, CC_NE0      ; leading zeros with CC set
```

### Pattern 3: SFPGT/SFPLE on BH (GH-Q-005)
```
; GCC currently generates (incorrect — doesn't use BH instructions):
sfpmad l0, l1, l2, l11, 0    ; t = a - b (using L11=-1.0)
sfpsetcc l0, 0, 0, 0         ; CC from t
sfpsetcc l0, 0, 0, 8         ; complement CC
; Should generate:
sfpgt l0, l1, 0, 0           ; direct comparison (BH only)
```
