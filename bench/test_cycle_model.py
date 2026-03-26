#!/usr/bin/env python3
"""
test_cycle_model.py — Validate the cycle-accurate SFPU model against known cases.

Tests:
1. Independent instructions: no stalls on BH, cycles = instruction count
2. Dependent chain: stalls on BH when reading 2-cycle producer immediately
3. Interleaved independent work fills the latency slot
4. SFPSWAP always stalls (static delay) even on BH
5. WH: NOPs are in the stream, no implicit stalls
6. Real kernel comparisons against expected cycle counts
"""

import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from cycle_model import simulate_cycles, compare_cycles, print_cycle_trace

tests_pass = 0
tests_fail = 0

def check(name, actual, expected, detail=""):
    global tests_pass, tests_fail
    if actual == expected:
        tests_pass += 1
        print(f"  [PASS] {name}: {actual}")
    else:
        tests_fail += 1
        print(f"  [FAIL] {name}: got {actual}, expected {expected}  {detail}")

print("=" * 70)
print("Cycle Model Validation")
print("=" * 70)

# ---- Test 1: All 1-cycle instructions, no dependencies ----
print("\n--- Test 1: Independent 1-cycle instructions ---")
insns = [
    "SFPLOAD\tL0, 0, 0, 0",
    "SFPLOAD\tL1, 0, 0, 16",
    "SFPMOV\tL2, L0, 0, 0",    # Reads L0, available immediately (1-cycle)
    "SFPABS\tL3, L1, 0, 0",    # Reads L1, available immediately
    "SFPSTORE\tL2, 0, 0, 0",
    "SFPSTORE\tL3, 0, 0, 16",
]
r = simulate_cycles(insns, bh=True)
check("BH cycles", r.total_cycles, 6, "(6 instructions, no stalls)")
check("BH stalls", r.stall_cycles, 0)

# ---- Test 2: Dependent read after 2-cycle MUL ----
print("\n--- Test 2: Dependent read after SFPMUL (2-cycle) ---")
insns = [
    "SFPMUL\tL0, L1, L2, L9, 0",   # 2-cycle: L0 ready at cycle 2
    "SFPMOV\tL3, L0, 0, 0",          # Reads L0: must wait until cycle 2
]
r = simulate_cycles(insns, bh=True)
check("BH cycles", r.total_cycles, 3, "(MUL@0, stall@1, MOV@2)")
check("BH stalls", r.stall_cycles, 1, "(1 dependency stall)")

# ---- Test 3: Independent work fills the latency slot ----
print("\n--- Test 3: Independent instruction fills MUL latency ---")
insns = [
    "SFPMUL\tL0, L1, L2, L9, 0",   # 2-cycle: L0 ready at cycle 2
    "SFPMOV\tL4, L3, 0, 0",          # Independent: no stall, fills slot
    "SFPMOV\tL5, L0, 0, 0",          # Reads L0: now ready (cycle 2), no stall
]
r = simulate_cycles(insns, bh=True)
check("BH cycles", r.total_cycles, 3, "(MUL@0, MOV@1(fills slot), MOV@2(L0 ready))")
check("BH stalls", r.stall_cycles, 0, "(independent work absorbed latency)")

# ---- Test 4: Two dependent MADs in sequence ----
print("\n--- Test 4: Dependent MAD chain ---")
insns = [
    "SFPMAD\tL0, L1, L2, L3, 0",    # L0 ready at cycle 2
    "SFPMAD\tL4, L0, L5, L6, 0",    # Reads L0: stall 1 cycle (issued at cycle 2)
]
r = simulate_cycles(insns, bh=True)
check("BH cycles", r.total_cycles, 3, "(MAD@0, stall, MAD@2)")
check("BH stalls", r.stall_cycles, 1)

# ---- Test 5: Two independent MADs — no stall ----
print("\n--- Test 5: Independent MADs (scheduler interleaving) ---")
insns = [
    "SFPMAD\tL0, L1, L2, L3, 0",    # L0 ready at cycle 2
    "SFPMAD\tL4, L5, L6, L7, 0",    # Independent: no stall
]
r = simulate_cycles(insns, bh=True)
check("BH cycles", r.total_cycles, 2, "(MAD@0, MAD@1, no stall)")
check("BH stalls", r.stall_cycles, 0)

# ---- Test 6: SFPSWAP always stalls (static delay) ----
print("\n--- Test 6: SFPSWAP static delay ---")
insns = [
    "SFPSWAP\tL0, L1, 0, 0",        # Static delay: always stall
    "SFPMOV\tL2, L3, 0, 0",          # Even independent: stall
]
r = simulate_cycles(insns, bh=True)
check("BH cycles", r.total_cycles, 3, "(SWAP@0, static stall@1, MOV@2)")
check("BH stalls", r.stall_cycles, 1, "(1 static stall)")

# ---- Test 7: GCC exp kernel with NOPs (WH model) ----
print("\n--- Test 7: WH model — NOPs already in stream ---")
insns = [
    "SFPMUL\tL2, L0, L8, L9, 0",
    "SFPNOP",
    "SFPADD\tL2, L10, L2, L9, 0",
]
r_wh = simulate_cycles(insns, bh=False)
check("WH cycles", r_wh.total_cycles, 3, "(3 instructions including NOP)")

# ---- Test 8: Real kernel comparison — exp Horner ----
print("\n--- Test 8: Real kernel — exp Horner 2-step ---")
gcc_insns = [
    "SFPLOAD\tL0, 0, 0, 0",
    "SFPEXEXP\tL1, L0, 0, 0",
    "SFPDIVP2\tL0, L1, 0, 0",
    "SFPMUL\tL2, L0, L8, L9, 0",
    "SFPNOP",
    "SFPADD\tL2, L10, L2, L9, 0",
    "SFPMUL\tL0, L0, L2, L9, 0",
    "SFPNOP",
    "SFPADD\tL0, L10, L0, L10, 0",
    "SFPSTORE\tL0, 0, 0, 0",
]
llvm_insns = [
    "SFPLOAD\tL0, 0, 0, 0",
    "SFPEXEXP\tL1, L0, 0, 0",
    "SFPDIVP2\tL0, L1, 0, 0",
    "SFPMAD\tL2, L0, L8, L9, 0",
    "SFPMAD\tL0, L0, L2, L10, 0",    # Dependent on L2: 1 stall
    "SFPSTORE\tL0, 0, 0, 0",
]

gcc_bh = simulate_cycles(gcc_insns, bh=True)
llvm_bh = simulate_cycles(llvm_insns, bh=True)

# GCC on BH: 10 instructions, MUL→ADD have dep stalls even with NOPs
# because GCC NOPs don't always fall between dependent pairs ideally.
# The model tracks real register dependencies through the stream.
print(f"  GCC BH: {gcc_bh.total_cycles} cycles, {gcc_bh.stall_cycles} stalls")
print(f"  LLVM BH: {llvm_bh.total_cycles} cycles, {llvm_bh.stall_cycles} stalls")

# Key check: LLVM has fewer cycles than GCC
cycle_savings = gcc_bh.total_cycles - llvm_bh.total_cycles
check("LLVM fewer cycles than GCC", cycle_savings > 0, True,
      f"({gcc_bh.total_cycles} → {llvm_bh.total_cycles}, saving {cycle_savings})")
check("LLVM fewer instructions", len(llvm_insns) < len(gcc_insns), True)

# ---- Test 9: Cycle trace for visualization ----
print("\n--- Test 9: Cycle trace — LLVM exp kernel (BH) ---")
print_cycle_trace(llvm_insns, bh=True)

# ---- Test 10: Independent MULs — LLVM interleaving advantage ----
print("\n--- Test 10: Independent MULs — scheduling advantage ---")
gcc_muls = [
    "SFPMUL\tL0, L1, L2, L9, 0",
    "SFPNOP",
    "SFPMUL\tL3, L4, L5, L9, 0",
    "SFPNOP",
]
llvm_muls = [
    "SFPMUL\tL0, L1, L2, L9, 0",
    "SFPMUL\tL3, L4, L5, L9, 0",     # Independent: fills latency slot
]

gcc_r = simulate_cycles(gcc_muls, bh=True)
llvm_r = simulate_cycles(llvm_muls, bh=True)

check("GCC independent MULs BH cycles", gcc_r.total_cycles, 4, "(4 insns including NOPs)")
check("LLVM independent MULs BH cycles", llvm_r.total_cycles, 2, "(2 insns, no stalls)")
check("Cycle savings", gcc_r.total_cycles - llvm_r.total_cycles, 2)

# ---- Summary ----
print(f"\n{'=' * 70}")
print(f"Cycle model validation: {tests_pass} passed, {tests_fail} failed")
print(f"{'=' * 70}")

sys.exit(1 if tests_fail > 0 else 0)
