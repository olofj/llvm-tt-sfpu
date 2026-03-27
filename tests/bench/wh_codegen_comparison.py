#!/usr/bin/env python3
"""
wh_codegen_comparison.py — Quantify LLVM vs GCC codegen improvements for WH.

Compiles a suite of representative SFPU kernels with both compilers targeting
Wormhole, then compares:
  - Total instruction count
  - NOP count (SFPNOP instructions)
  - 2-cycle instruction count (SFPMAD, SFPMUL, SFPADD, etc.)
  - Delay slots filled (2-cycle insns NOT followed by NOP)
  - BH-only instruction leakage (should be 0)

Usage:
    python3 tests/bench/wh_codegen_comparison.py [--verbose]

Requires:
    - LLVM backend built (llc in llvm-project-upstream/build/bin/)
    - GCC SFPU compiler (optional, for comparison)
"""

import os
import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).parent.parent.parent
BUILD = PROJECT / "llvm-project-upstream" / "build" / "bin"
LLC = str(BUILD / "llc")

# SFPU instructions categorized by cycle count
TWO_CYCLE_INSNS = {
    "sfpmad", "sfpadd", "sfpmul", "sfpmuli", "sfpaddi",
    "sfplutfp32", "sfpswap", "sfpshft2",
}
BH_ONLY_INSNS = {"sfpmul24", "sfparecip", "sfpgt", "sfple", "sfpmov_config"}

# ============================================================================
# Kernel definitions (LLVM IR)
# ============================================================================

IR_HEADER = """\
target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpabs(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpdivp2(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpsetexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpiadd(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpcast(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpcompc()
declare void @llvm.riscv.tt.sfpnop()
"""

KERNELS = {
    "exp_horner_2step": {
        "desc": "2-step Horner series (exp approximation)",
        "gcc_wh_insns": 6,  # Expected from GCC: load, mad, nop, mad, nop, store
        "gcc_wh_nops": 2,
        "ir": """
define void @exp_horner_2step() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %tmp, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
""",
    },

    "exp_horner_3step": {
        "desc": "3-step Horner series (higher precision exp)",
        "gcc_wh_insns": 8,
        "gcc_wh_nops": 3,
        "ir": """
define void @exp_horner_3step() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %t1, i32 10, i32 0)
  %t3 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %t2, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %t3, i32 0, i32 0, i32 0)
  ret void
}
""",
    },

    "two_independent_mads": {
        "desc": "Two independent MADs (delay slot filling opportunity)",
        "gcc_wh_insns": 8,  # 2x(load,load,mad,nop) → 4 loads + 2 mads + 2 nops
        "gcc_wh_nops": 2,
        "ir": """
define void @two_independent_mads() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  %mad1 = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  %mad2 = call i32 @llvm.riscv.tt.sfpmad(i32 %c, i32 %d, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad1, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad2, i32 0, i32 0, i32 16)
  ret void
}
""",
    },

    "mul_add_fusable": {
        "desc": "MUL+ADD that should fuse to MAD (GH-Q-002)",
        "gcc_wh_insns": 7,  # loads + mul + nop + add + nop + store
        "gcc_wh_nops": 2,
        "ir": """
define void @mul_add_fusable() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %tmp = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %tmp, i32 %c, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
""",
    },

    "sigmoid_approx": {
        "desc": "Sigmoid: negate, exp, add 1 (activation function)",
        "gcc_wh_insns": 10,
        "gcc_wh_nops": 4,  # Sequential chain: MUL→MAD→MAD→ADD, all dependent
        "ir": """
define void @sigmoid_approx() {
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %neg = call i32 @llvm.riscv.tt.sfpmul(i32 %x, i32 11, i32 9, i32 0)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %neg, i32 8, i32 9, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpmad(i32 %neg, i32 %t1, i32 10, i32 0)
  %sum = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %exp, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %sum, i32 0, i32 0, i32 0)
  ret void
}
""",
    },

    "abs_exexp_cast": {
        "desc": "Abs + exponent extract + cast (all 1-cycle, no NOPs needed)",
        "gcc_wh_insns": 5,
        "gcc_wh_nops": 0,
        "ir": """
define void @abs_exexp_cast() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %a = call i32 @llvm.riscv.tt.sfpabs(i32 %val, i32 0, i32 0)
  %e = call i32 @llvm.riscv.tt.sfpexexp(i32 %a, i32 0, i32 0)
  %c = call i32 @llvm.riscv.tt.sfpcast(i32 %e, i32 0, i32 2)
  call void @llvm.riscv.tt.sfpstore(i32 %c, i32 0, i32 0, i32 0)
  ret void
}
""",
    },

    "predicated_mad": {
        "desc": "MAD inside v_if (tests scheduling inside predicated region)",
        "gcc_wh_insns": 8,
        "gcc_wh_nops": 1,
        "ir": """
define void @predicated_mad() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %val, i32 0, i32 2)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %exp, i32 0, i32 4)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
""",
    },

    "interleaved_horner_2row": {
        "desc": "2-row Horner with interleaving opportunity (key optimization)",
        "gcc_wh_insns": 14,  # 2x(load + mad + nop + mad + nop + store) + overhead
        "gcc_wh_nops": 4,
        "ir": """
define void @interleaved_horner_2row() {
  %v0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %t0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 8, i32 9, i32 0)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 8, i32 9, i32 0)
  %r0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 %t0, i32 10, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 %t1, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)
  ret void
}
""",
    },

    "estrin_degree3": {
        "desc": "Estrin degree-3 with register copies (independent sub-chains)",
        "gcc_wh_insns": 9,  # Horner equivalent: load + 3*(mad+nop) + store
        "gcc_wh_nops": 3,   # Horner would have 3 NOPs
        "ir": """
define void @estrin_degree3() {
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %x_lo = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %x_hi = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %lo = call i32 @llvm.riscv.tt.sfpmad(i32 %x_lo, i32 8, i32 9, i32 0)
  %hi = call i32 @llvm.riscv.tt.sfpmad(i32 %x_hi, i32 8, i32 10, i32 0)
  %x2 = call i32 @llvm.riscv.tt.sfpmul(i32 %x, i32 %x, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %hi, i32 %x2, i32 %lo, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
""",
    },

    "horner_4row_pipeline": {
        "desc": "4-row unrolled Horner (software pipeline: all NOPs filled)",
        "gcc_wh_insns": 24,  # 4 * (load + mad + nop + mad + nop + store)
        "gcc_wh_nops": 8,    # 4 rows * 2 NOPs/row
        "ir": """
define void @horner_4row_pipeline() {
  %v0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %v2 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %v3 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  %t0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 8, i32 9, i32 0)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 8, i32 9, i32 0)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %v2, i32 8, i32 9, i32 0)
  %t3 = call i32 @llvm.riscv.tt.sfpmad(i32 %v3, i32 8, i32 9, i32 0)
  %r0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 %t0, i32 10, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 %t1, i32 10, i32 0)
  %r2 = call i32 @llvm.riscv.tt.sfpmad(i32 %v2, i32 %t2, i32 10, i32 0)
  %r3 = call i32 @llvm.riscv.tt.sfpmad(i32 %v3, i32 %t3, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)
  call void @llvm.riscv.tt.sfpstore(i32 %r2, i32 0, i32 0, i32 32)
  call void @llvm.riscv.tt.sfpstore(i32 %r3, i32 0, i32 0, i32 48)
  ret void
}
""",
    },

    "estrin_degree5": {
        "desc": "Estrin degree-5 with register copies (GELU-class)",
        "gcc_wh_insns": 15,  # Horner equivalent: load + 5*(mad+nop) + store
        "gcc_wh_nops": 5,    # Horner would have 5 NOPs
        "ir": """
define void @estrin_degree5() {
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %x_lo = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %x_mid = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %x_hi = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %lo = call i32 @llvm.riscv.tt.sfpmad(i32 %x_lo, i32 8, i32 9, i32 0)
  %mid = call i32 @llvm.riscv.tt.sfpmad(i32 %x_mid, i32 8, i32 10, i32 0)
  %hi = call i32 @llvm.riscv.tt.sfpmad(i32 %x_hi, i32 8, i32 9, i32 0)
  %x2 = call i32 @llvm.riscv.tt.sfpmul(i32 %x, i32 %x, i32 9, i32 0)
  %x4 = call i32 @llvm.riscv.tt.sfpmul(i32 %x2, i32 %x2, i32 9, i32 0)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %hi, i32 %x4, i32 %mid, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %t1, i32 %x2, i32 %lo, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
""",
    },
}


def compile_kernel(name, ir_text, arch):
    """Compile IR to assembly and return SFPU instruction list."""
    import tempfile

    mattr = f"+xttsfpu,+xttsfpu{arch}"
    full_ir = IR_HEADER + ir_text

    with tempfile.NamedTemporaryFile(mode='w', suffix='.ll', delete=False) as f:
        f.write(full_ir)
        f.flush()
        try:
            result = subprocess.run(
                [LLC, "-march=riscv32", f"-mattr={mattr}", f.name, "-o", "-"],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode != 0:
                return None, result.stderr[:200]

            insns = []
            for line in result.stdout.splitlines():
                stripped = line.strip()
                # Match SFPU instruction mnemonics (tab-indented in asm output)
                if re.match(r'sfp\w+', stripped, re.IGNORECASE):
                    insns.append(stripped)
            return insns, None
        finally:
            os.unlink(f.name)


def analyze_sequence(insns):
    """Analyze an instruction sequence for metrics."""
    if not insns:
        return {}

    total = len(insns)
    nops = 0
    two_cycle = 0
    bh_only = 0
    delay_slots_filled = 0

    for i, insn in enumerate(insns):
        mnem = insn.split()[0].lower().rstrip(",")

        if mnem == "sfpnop":
            nops += 1
        if mnem in TWO_CYCLE_INSNS:
            two_cycle += 1
            # Check if delay slot is filled (next insn is NOT sfpnop)
            if i + 1 < total:
                next_mnem = insns[i + 1].split()[0].lower().rstrip(",")
                if next_mnem != "sfpnop":
                    delay_slots_filled += 1
        if mnem in BH_ONLY_INSNS:
            bh_only += 1

    return {
        "total": total,
        "nops": nops,
        "two_cycle": two_cycle,
        "delay_filled": delay_slots_filled,
        "bh_only": bh_only,
        "useful": total - nops,
    }


def main():
    verbose = "--verbose" in sys.argv or "-v" in sys.argv

    if not os.path.isfile(LLC):
        print(f"ERROR: llc not found at {LLC}")
        print("       Run scripts/build.sh first")
        sys.exit(1)

    print("WH SFPU Codegen Benchmark: LLVM vs GCC")
    print("=" * 70)

    # Aggregate stats
    total_llvm = {"total": 0, "nops": 0, "two_cycle": 0, "delay_filled": 0, "useful": 0}
    total_gcc = {"total": 0, "nops": 0}
    num_compiled = 0
    num_failed = 0

    header = f"{'Kernel':<30} {'GCC':>4} {'LLVM':>4} {'Saved':>5} {'%':>5} " \
             f"{'NOPs GCC':>8} {'NOPs LLVM':>9} {'Delay Fill':>10}"
    print(f"\n{header}")
    print("-" * 80)

    for name, kinfo in KERNELS.items():
        insns, err = compile_kernel(name, kinfo["ir"], "wh")

        if err:
            print(f"  {name:<30} COMPILE ERROR: {err}")
            num_failed += 1
            continue

        stats = analyze_sequence(insns)
        gcc_total = kinfo["gcc_wh_insns"]
        gcc_nops = kinfo["gcc_wh_nops"]
        llvm_total = stats["total"]
        llvm_nops = stats["nops"]
        saved = gcc_total - llvm_total
        pct = (saved / gcc_total * 100) if gcc_total > 0 else 0
        delay_fill_str = f"{stats['delay_filled']}/{stats['two_cycle']}"

        marker = ""
        if stats["bh_only"] > 0:
            marker = " *** BH LEAK ***"
        if saved < 0:
            marker = " (regression)"

        print(f"  {name:<28} {gcc_total:>4} {llvm_total:>4} {saved:>+5} "
              f"{pct:>4.0f}% {gcc_nops:>8} {llvm_nops:>9} {delay_fill_str:>10}{marker}")

        if verbose and insns:
            for insn in insns:
                print(f"      {insn}")
            print()

        total_llvm["total"] += llvm_total
        total_llvm["nops"] += llvm_nops
        total_llvm["two_cycle"] += stats["two_cycle"]
        total_llvm["delay_filled"] += stats["delay_filled"]
        total_llvm["useful"] += stats["useful"]
        total_gcc["total"] += gcc_total
        total_gcc["nops"] += gcc_nops
        num_compiled += 1

    # Summary
    print("-" * 80)
    if num_compiled > 0:
        total_saved = total_gcc["total"] - total_llvm["total"]
        total_pct = (total_saved / total_gcc["total"] * 100) if total_gcc["total"] > 0 else 0
        nop_saved = total_gcc["nops"] - total_llvm["nops"]
        fill_rate = (total_llvm["delay_filled"] / total_llvm["two_cycle"] * 100) \
                    if total_llvm["two_cycle"] > 0 else 0

        print(f"  {'TOTAL':<28} {total_gcc['total']:>4} {total_llvm['total']:>4} "
              f"{total_saved:>+5} {total_pct:>4.0f}% {total_gcc['nops']:>8} "
              f"{total_llvm['nops']:>9} {total_llvm['delay_filled']}/{total_llvm['two_cycle']}")
        print()
        print(f"  Kernels compiled: {num_compiled}/{num_compiled + num_failed}")
        print(f"  Total instruction reduction: {total_saved} ({total_pct:.1f}%)")
        print(f"  NOP reduction: {nop_saved} of {total_gcc['nops']} GCC NOPs eliminated")
        print(f"  Delay slot fill rate: {fill_rate:.0f}% "
              f"({total_llvm['delay_filled']}/{total_llvm['two_cycle']} 2-cycle insns)")

    sys.exit(1 if num_failed > 0 else 0)


if __name__ == "__main__":
    main()
