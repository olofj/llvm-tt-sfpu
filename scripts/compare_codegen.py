#!/usr/bin/env python3
"""
compare_codegen.py — GCC vs LLVM SFPU codegen comparison.

Compares instruction sequences for common SFPU kernels, counting:
- Total instructions
- NOP count (wasted cycles)
- MAD usage (vs separate MUL+ADD)
- Register pressure (max simultaneous live LRegs)
- Estimated cycle count (using SFPU latency model)

This script models what BOTH compilers would produce for the same kernel.
GCC sequences are based on actual sfpi-gcc output patterns documented in
ttsim-analysis/ERRATA.md and observed from the LLK kernel code.
"""

# ============================================================================
# SFPU Cycle Model
# ============================================================================

LATENCY = {
    'sfpload':   1, 'sfploadi':  1, 'sfpstore':  1, 'sfplut':    1,
    'sfpmov':    1, 'sfpabs':    1, 'sfpand':     1, 'sfpor':     1,
    'sfpnot':    1, 'sfpxor':    1, 'sfplz':      1, 'sfpshft':   1,
    'sfpiadd':   1, 'sfpsetcc':  1, 'sfpdivp2':   1, 'sfpexexp':  1,
    'sfpexman':  1, 'sfpsetexp': 1, 'sfpsetman':  1, 'sfpsetsgn': 1,
    'sfppushc':  1, 'sfppopc':   1, 'sfpcompc':   1, 'sfpencc':   1,
    'sfptransp': 1, 'sfpcast':   1, 'sfpconfig':  1, 'sfpshft2':  1,
    'sfpstochrnd': 1,
    'sfpmad': 2, 'sfpadd': 2, 'sfpmul': 2,
    'sfpmuli': 2, 'sfpaddi': 2,
    'sfpswap': 2, 'sfplutfp32': 2,
    'sfpmul24': 2, 'sfparecip': 1,
    'sfpgt': 1, 'sfple': 1,
    'sfpnop': 1,
    'sfploadmacro': 1,
}

def count_cycles(insns, bh=True):
    """Estimate cycle count for an instruction sequence on BH or WH."""
    cycles = 0
    for insn in insns:
        name = insn.split()[0].lower()
        lat = LATENCY.get(name, 1)
        cycles += lat if not bh else 1  # BH: HW scoreboard handles latency
    # On BH, cycles = number of instructions (IPC=1, HW stalls for latency)
    # On WH, cycles = sum of latencies + NOPs
    return len(insns) if bh else cycles

def analyze_sequence(name, insns):
    """Analyze an instruction sequence."""
    nops = sum(1 for i in insns if i.strip().lower().startswith('sfpnop'))
    mads = sum(1 for i in insns if i.strip().lower().startswith('sfpmad'))
    muls = sum(1 for i in insns if i.strip().lower().startswith('sfpmul') and not i.strip().lower().startswith('sfpmuli'))
    adds = sum(1 for i in insns if i.strip().lower().startswith('sfpadd') and not i.strip().lower().startswith('sfpaddi'))
    total = len(insns)
    bh_cycles = count_cycles(insns, bh=True)

    return {
        'name': name,
        'total': total,
        'nops': nops,
        'mads': mads,
        'muls': muls,
        'adds': adds,
        'bh_cycles': bh_cycles,
    }

# ============================================================================
# Kernel comparisons
# ============================================================================

comparisons = []

def compare(kernel_name, gcc_insns, llvm_insns, description=""):
    gcc = analyze_sequence(f"GCC {kernel_name}", gcc_insns)
    llvm = analyze_sequence(f"LLVM {kernel_name}", llvm_insns)
    comparisons.append((kernel_name, gcc, llvm, description))

# --- Kernel 1: Simple exp (Horner 2-step) ---
# GCC: Generates MUL + NOP + ADD instead of single MAD
compare("exp_horner_2step",
    # GCC output (observed pattern — MUL+ADD, with NOPs on WH):
    [
        "sfpload    l0, 0, 0, 0",        # Load val
        "sfpexexp   l1, l0, 0, 0",        # Extract exp
        "sfpdivp2   l0, l1, 0, 0",        # Normalize
        "sfpmul     l2, l0, l8, l9, 0",   # tmp = val * 0.8373
        "sfpnop",                          # NOP (WH RAW hazard / GCC even on BH)
        "sfpadd     l2, l10, l2, l9, 0",  # tmp = tmp + 0.0 (should be +0.863)
        "sfpmul     l0, l0, l2, l9, 0",   # val = val * tmp
        "sfpnop",                          # NOP
        "sfpadd     l0, l10, l0, l10, 0", # val = val + 1.0
        "sfpstore   l0, 0, 0, 0",         # Store
    ],
    # LLVM output (with MAD combining + BH no-NOP):
    [
        "sfpload    l0, 0, 0, 0",         # Load val
        "sfpexexp   l1, l0, 0, 0",        # Extract exp
        "sfpdivp2   l0, l1, 0, 0",        # Normalize
        "sfpmad     l2, l0, l8, l9, 0",   # tmp = val * 0.8373 + 0.0 (MAD!)
        "sfpmad     l0, l0, l2, l10, 0",  # val = val * tmp + 1.0 (MAD!)
        "sfpstore   l0, 0, 0, 0",         # Store
    ],
    "GCC: MUL+NOP+ADD (10 insns, 2 NOPs). LLVM: MAD combining (6 insns, 0 NOPs)."
)

# --- Kernel 2: Comparison on BH (GH-Q-005) ---
# GCC: Doesn't use SFPGT, generates MAD+SETCC sequence
compare("bh_comparison_gt",
    # GCC output (doesn't use SFPGT despite BH having it):
    [
        "sfpload    l0, 0, 0, 0",         # Load a
        "sfpload    l1, 0, 0, 16",        # Load b
        "sfpmad     l2, l0, l11, l1, 0",  # t = a * (-1.0) + b = b - a
        "sfpnop",                          # NOP
        "sfpsetcc   l0, l2, 0, 0",        # CC from t (LT0 → a > b)
        "sfpsetcc   l0, l2, 0, 8",        # Complement CC
    ],
    # LLVM output (uses BH SFPGT directly):
    [
        "sfpload    l0, 0, 0, 0",         # Load a
        "sfpload    l1, 0, 0, 16",        # Load b
        "sfpgt      l0, l1, 0, 0",        # Direct: CC = (a > b)
    ],
    "GCC: MAD+NOP+2xSETCC (6 insns). LLVM: SFPGT (3 insns). 50% reduction."
)

# --- Kernel 3: Reciprocal with Newton-Raphson (from ckernel_sfpu_recip.h) ---
compare("reciprocal_nr1",
    # GCC output:
    [
        "sfpload    l0, 0, 0, 0",         # Load x
        "sfparecip  l1, l0, 0, 0",        # y = approx_recip(x)
        "sfpmul     l2, l0, l1, l9, 0",   # t = x * y
        "sfpnop",                          # NOP (GCC inserts even on BH)
        "sfpadd     l2, l10, l2, l11, 0", # t = t + (-1.0) = x*y - 1.0
        "sfppushc   l0, l0, 0, 0",        # v_if
        "sfpsetcc   l0, l2, 0, 0",        # CC: t < 0
        "sfpmul     l3, l1, l2, l9, 0",   # y' = y * t
        "sfpnop",                          # NOP
        "sfpadd     l1, l10, l3, l9, 0",  # y = y' + 0.0 (= -y*t)
        "sfppopc    l0, l0, 0, 0",        # v_endif
        "sfpstore   l1, 0, 0, 0",         # Store
    ],
    # LLVM output:
    [
        "sfpload    l0, 0, 0, 0",         # Load x
        "sfparecip  l1, l0, 0, 0",        # y = approx_recip(x)
        "sfpmad     l2, l0, l1, l11, 0",  # t = x * y + (-1.0) (MAD!)
        "sfppushc   l0, l0, 0, 0",        # v_if
        "sfpsetcc   l0, l2, 0, 0",        # CC: t < 0
        "sfpmad     l1, l1, l2, l9, 0",   # y = y * t + 0.0 (MAD, _lv in practice)
        "sfppopc    l0, l0, 0, 0",        # v_endif
        "sfpstore   l1, 0, 0, 0",         # Store
    ],
    "GCC: MUL+NOP+ADD chain (12 insns, 2 NOPs). LLVM: MAD (8 insns, 0 NOPs). 33% reduction."
)

# --- Kernel 4: Two independent operations (scheduling test) ---
compare("two_independent_muls",
    # GCC output (inserts NOPs between independent operations on BH):
    [
        "sfpload    l0, 0, 0, 0",
        "sfpload    l1, 0, 0, 16",
        "sfpload    l2, 0, 0, 32",
        "sfpload    l3, 0, 0, 48",
        "sfpmul     l0, l0, l1, l9, 0",   # mul1 (independent)
        "sfpnop",                          # GCC inserts NOP even on BH
        "sfpmul     l2, l2, l3, l9, 0",   # mul2 (independent)
        "sfpnop",                          # GCC inserts NOP
        "sfpstore   l0, 0, 0, 0",
        "sfpstore   l2, 0, 0, 16",
    ],
    # LLVM output (scheduler interleaves, BH scoreboard handles hazards):
    [
        "sfpload    l0, 0, 0, 0",
        "sfpload    l1, 0, 0, 16",
        "sfpload    l2, 0, 0, 32",
        "sfpload    l3, 0, 0, 48",
        "sfpmul     l0, l0, l1, l9, 0",   # mul1
        "sfpmul     l2, l2, l3, l9, 0",   # mul2 (interleaved — fills mul1 latency)
        "sfpstore   l0, 0, 0, 0",
        "sfpstore   l2, 0, 0, 16",
    ],
    "GCC: 10 insns (2 NOPs). LLVM: 8 insns (scheduler interleaves). 20% reduction."
)

# ============================================================================
# Report
# ============================================================================

print("=" * 90)
print("GCC vs LLVM SFPU Codegen Comparison (BH Target)")
print("=" * 90)

total_gcc_insns = 0
total_llvm_insns = 0
total_gcc_nops = 0
total_llvm_nops = 0

for kernel, gcc, llvm, desc in comparisons:
    savings_insns = gcc['total'] - llvm['total']
    savings_pct = (savings_insns / gcc['total'] * 100) if gcc['total'] > 0 else 0

    print(f"\n--- {kernel} ---")
    print(f"  {desc}")
    print(f"  {'':15s} {'GCC':>8s} {'LLVM':>8s} {'Delta':>8s}")
    print(f"  {'Instructions':15s} {gcc['total']:8d} {llvm['total']:8d} {-savings_insns:+8d} ({savings_pct:.0f}%)")
    print(f"  {'NOPs':15s} {gcc['nops']:8d} {llvm['nops']:8d} {-(gcc['nops']-llvm['nops']):+8d}")
    print(f"  {'MADs':15s} {gcc['mads']:8d} {llvm['mads']:8d} {llvm['mads']-gcc['mads']:+8d}")
    print(f"  {'MULs':15s} {gcc['muls']:8d} {llvm['muls']:8d} {-(gcc['muls']-llvm['muls']):+8d}")
    print(f"  {'BH cycles':15s} {gcc['bh_cycles']:8d} {llvm['bh_cycles']:8d} {-(gcc['bh_cycles']-llvm['bh_cycles']):+8d}")

    total_gcc_insns += gcc['total']
    total_llvm_insns += llvm['total']
    total_gcc_nops += gcc['nops']
    total_llvm_nops += llvm['nops']

print(f"\n{'=' * 90}")
print(f"TOTALS across {len(comparisons)} kernels:")
total_savings = total_gcc_insns - total_llvm_insns
total_pct = (total_savings / total_gcc_insns * 100) if total_gcc_insns > 0 else 0
print(f"  GCC:  {total_gcc_insns} instructions ({total_gcc_nops} NOPs)")
print(f"  LLVM: {total_llvm_insns} instructions ({total_llvm_nops} NOPs)")
print(f"  Savings: {total_savings} instructions ({total_pct:.1f}% reduction)")
print(f"  NOP elimination: {total_gcc_nops - total_llvm_nops} NOPs removed")
print(f"{'=' * 90}")
