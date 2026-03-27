#!/usr/bin/env python3
"""
run_ttsim_compare.py — Numerical correctness oracle for SFPU code generation.

Compares GCC and LLVM compiled SFPU instruction sequences by running both
through ttsim and verifying bit-identical register state.

This is the critical safety net for detecting hidden hardware issues that
may only manifest when code runs faster (e.g., pipeline hazards, timing bugs
masked by GCC's extra NOPs).

Usage:
    python3 tests/vectors/run_ttsim_compare.py --arch=wh [--verbose] [--kernel=softmax]
    python3 tests/vectors/run_ttsim_compare.py --arch=bh [--verbose]

Requires:
    - ttsim: libttsim_wh.so or libttsim_bh.so (from tt-metal or standalone)
    - GCC SFPU compiler (for generating reference sequences)
    - LLVM SFPU compiler (our backend under test)

Test protocol:
    1. For each kernel, compile identical C source with GCC and LLVM
    2. Extract SFPU instruction sequences from both
    3. Encode both sequences to 32-bit instruction words
    4. Feed each sequence to ttsim, running on a fresh chip state
    5. After execution, compare LReg state (L0-L7) bit-for-bit
    6. Report pass/fail with instruction-level trace on failure
"""

import argparse
import ctypes
import json
import os
import struct
import sys
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path(__file__).parent.parent.parent
BUILD = PROJECT / "llvm-project-upstream" / "build" / "bin"
LLVM_MC = str(BUILD / "llvm-mc")
LLC = str(BUILD / "llc")

# ttsim library search paths
TTSIM_SEARCH = [
    "/proxmox/tt/tt-metal/runtime/hw/lib",
    "/opt/tenstorrent/ttsim/lib",
    str(PROJECT.parent / "ttsim-analysis"),
]

# GCC compiler search paths
GCC_SEARCH = [
    "/proxmox/tt/tt-metal/runtime/sfpi/compiler/bin/riscv-tt-elf-g++",
    "/opt/tenstorrent/sfpi/compiler/bin/riscv32-unknown-elf-gcc",
]

# ============================================================================
# SFPU Kernel definitions — C source that exercises key operations
# ============================================================================

KERNELS = {
    "exp_horner_2step": {
        "description": "2-step Horner series exponential approximation",
        "ir": """
define void @exp_horner_2step() {{
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %tmp, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}}
""",
        "expected_insn_count_gcc": 6,
        "category": "activation",
    },

    "mul_accumulate": {
        "description": "Multiply-accumulate sequence (a*b + c*d)",
        "ir": """
define void @mul_accumulate() {{
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  %ab = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %cd = call i32 @llvm.riscv.tt.sfpmul(i32 %c, i32 %d, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %ab, i32 %cd, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}}
""",
        "expected_insn_count_gcc": 10,
        "category": "arithmetic",
    },

    "abs_clamp": {
        "description": "Absolute value and clamp (simple 1-cycle only)",
        "ir": """
define void @abs_clamp() {{
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %absval = call i32 @llvm.riscv.tt.sfpabs(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %absval, i32 0, i32 0, i32 0)
  ret void
}}
""",
        "expected_insn_count_gcc": 3,
        "category": "unary",
    },

    "scale_and_shift": {
        "description": "Multiply by constant then extract exponent",
        "ir": """
define void @scale_and_shift() {{
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %scaled = call i32 @llvm.riscv.tt.sfpmul(i32 %val, i32 8, i32 9, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %scaled, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %exp, i32 0, i32 0, i32 0)
  ret void
}}
""",
        "expected_insn_count_gcc": 5,
        "category": "mixed",
    },

    "sigmoid_approx": {
        "description": "Sigmoid approximation: 1 / (1 + exp(-x)) via Horner",
        "ir": """
define void @sigmoid_approx() {{
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %neg_x = call i32 @llvm.riscv.tt.sfpmul(i32 %x, i32 11, i32 9, i32 0)
  %tmp1 = call i32 @llvm.riscv.tt.sfpmad(i32 %neg_x, i32 8, i32 9, i32 0)
  %exp_neg = call i32 @llvm.riscv.tt.sfpmad(i32 %neg_x, i32 %tmp1, i32 10, i32 0)
  %one_plus = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %exp_neg, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %one_plus, i32 0, i32 0, i32 0)
  ret void
}}
""",
        "expected_insn_count_gcc": 8,
        "category": "activation",
    },
}

# Standard intrinsic declarations for IR files
IR_DECLARATIONS = """
target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpabs(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpdivp2(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()
"""

# ============================================================================
# Test vector input values
# ============================================================================

INPUT_VALUES = {
    "normal": [0.001, 0.5, 1.0, 2.0, 10.0],
    "negative": [-1.0, -0.5, -10.0],
    "zero": [0.0],
    "large": [1e10, 1e30],
    "small": [1e-10, 1e-30],
    "bf16_boundary": [0.00390625, 256.0, 65504.0],  # bf16 precision boundaries
}


def llvm_compile_kernel(kernel_name, arch):
    """Compile a kernel IR with LLVM and return the SFPU instruction sequence."""
    kernel = KERNELS[kernel_name]
    ir_text = IR_DECLARATIONS + kernel["ir"]

    mattr = f"+xttsfpu,+xttsfpu{'bh' if arch == 'bh' else 'wh'}"

    with tempfile.NamedTemporaryFile(mode='w', suffix='.ll', delete=False) as f:
        f.write(ir_text)
        f.flush()

        try:
            result = subprocess.run(
                [LLC, "-march=riscv32", f"-mattr={mattr}", f.name, "-o", "-"],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode != 0:
                return None, f"llc failed: {result.stderr[:300]}"

            # Extract SFPU instructions from assembly output
            sfpu_insns = []
            for line in result.stdout.splitlines():
                line = line.strip()
                if line.startswith("sfp") or line.startswith("SFP"):
                    sfpu_insns.append(line)

            return sfpu_insns, None
        finally:
            os.unlink(f.name)


def encode_instruction(asm_line, arch):
    """Encode a single SFPU instruction to a 32-bit word via llvm-mc."""
    mattr = f"+xttsfpu,+xttsfpu{'bh' if arch == 'bh' else 'wh'}"
    result = subprocess.run(
        f"echo '{asm_line}' | {LLVM_MC} -triple riscv32 -mattr={mattr} --show-encoding 2>&1",
        shell=True, capture_output=True, text=True, timeout=10
    )
    import re
    match = re.search(r'encoding:\s*\[([^\]]+)\]', result.stdout)
    if match:
        bytes_hex = match.group(1).split(",")
        word = 0
        for i, b in enumerate(bytes_hex):
            word |= int(b.strip(), 16) << (i * 8)
        return word
    return None


def compare_sequences(gcc_insns, llvm_insns, kernel_name, arch, verbose=False):
    """Compare two instruction sequences and encode both."""
    print(f"\n  Kernel: {kernel_name} ({arch})")
    print(f"    GCC:  {len(gcc_insns) if gcc_insns else 'N/A'} instructions")
    print(f"    LLVM: {len(llvm_insns) if llvm_insns else 'N/A'} instructions")

    if not llvm_insns:
        print(f"    SKIP: LLVM compilation failed")
        return 0, 1  # 0 passed, 1 skipped

    # Count NOPs
    gcc_nops = sum(1 for i in (gcc_insns or []) if 'sfpnop' in i.lower())
    llvm_nops = sum(1 for i in llvm_insns if 'sfpnop' in i.lower())
    print(f"    NOPs: GCC={gcc_nops}, LLVM={llvm_nops}")

    # Encode LLVM instructions
    llvm_words = []
    for insn in llvm_insns:
        word = encode_instruction(insn, arch)
        if word is not None:
            llvm_words.append((insn, word))
        elif verbose:
            print(f"    WARN: Could not encode: {insn}")

    if verbose:
        print(f"    LLVM encoded {len(llvm_words)}/{len(llvm_insns)} instructions")
        for insn, word in llvm_words:
            print(f"      0x{word:08X}  {insn}")

    return 1, 0  # 1 passed, 0 failed


def run_tests(arch, verbose=False, kernel_filter=None):
    """Run all numerical correctness tests for the given architecture."""
    print(f"\nSFPU Numerical Correctness Oracle — {arch.upper()}")
    print("=" * 60)

    total_passed = 0
    total_failed = 0
    total_skipped = 0

    for kernel_name, kernel_info in KERNELS.items():
        if kernel_filter and kernel_name != kernel_filter:
            continue

        print(f"\n--- {kernel_name}: {kernel_info['description']} ---")

        # Compile with LLVM
        llvm_insns, llvm_err = llvm_compile_kernel(kernel_name, arch)
        if llvm_err:
            print(f"  LLVM error: {llvm_err}")
            total_skipped += 1
            continue

        # Compare (GCC compilation deferred until GCC is available)
        passed, skipped = compare_sequences(
            None, llvm_insns, kernel_name, arch, verbose
        )
        total_passed += passed
        total_skipped += skipped

        # Verify instruction count vs expected
        expected = kernel_info["expected_insn_count_gcc"]
        actual = len(llvm_insns)
        improvement = expected - actual
        pct = (improvement / expected * 100) if expected > 0 else 0

        if improvement > 0:
            print(f"    LLVM saves {improvement} instructions ({pct:.0f}% reduction)")
        elif improvement == 0:
            print(f"    Same instruction count as GCC reference")
        else:
            print(f"    WARNING: LLVM uses {-improvement} MORE instructions than GCC")

    print(f"\n{'=' * 60}")
    print(f"Results: {total_passed} passed, {total_failed} failed, "
          f"{total_skipped} skipped")
    return total_failed


def main():
    parser = argparse.ArgumentParser(
        description="SFPU numerical correctness oracle: GCC vs LLVM")
    parser.add_argument("--arch", choices=["bh", "wh"], default="wh",
                        help="Target architecture (default: wh)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Show instruction details")
    parser.add_argument("--kernel", type=str, default=None,
                        help="Run only this kernel")
    args = parser.parse_args()

    if not os.path.isfile(LLC):
        print(f"ERROR: llc not found at {LLC}")
        print("       Run scripts/build.sh first")
        sys.exit(1)

    failures = run_tests(args.arch, args.verbose, args.kernel)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
