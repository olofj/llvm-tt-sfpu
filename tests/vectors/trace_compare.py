#!/usr/bin/env python3
"""
trace_compare.py — Instruction-level trace comparator for SFPU sequences.

When the numerical correctness oracle (run_ttsim_compare.py) detects a
divergence between GCC and LLVM compiled code, this tool provides detailed
instruction-by-instruction tracing to identify the exact point of failure.

Usage:
    python3 tests/vectors/trace_compare.py \
        --gcc-sequence gcc_insns.json \
        --llvm-sequence llvm_insns.json \
        --arch wh

Each input JSON file contains:
{
    "kernel": "softmax",
    "arch": "wh",
    "instructions": [
        {"asm": "sfpload l0, 0, 0, 0", "word": "0x70000003"},
        {"asm": "sfpmad l0, l0, l8, l9, 0", "word": "0x84089003"},
        ...
    ]
}

Output: side-by-side trace showing register state after each instruction,
highlighting the first divergence point.
"""

import argparse
import json
import struct
import sys
from pathlib import Path


def load_sequence(filepath):
    """Load an instruction sequence from a JSON file."""
    with open(filepath) as f:
        data = json.load(f)
    return data


def format_fp32_bits(word):
    """Format a 32-bit integer as IEEE 754 float for display."""
    try:
        value = struct.unpack('f', struct.pack('I', word & 0xFFFFFFFF))[0]
        return f"0x{word:08X} ({value:12.6g})"
    except (struct.error, OverflowError):
        return f"0x{word:08X} (invalid)"


def compare_traces(gcc_data, llvm_data, verbose=False):
    """Compare two instruction traces and identify the first divergence."""
    gcc_insns = gcc_data.get("instructions", [])
    llvm_insns = llvm_data.get("instructions", [])

    print(f"GCC  sequence: {len(gcc_insns)} instructions")
    print(f"LLVM sequence: {len(llvm_insns)} instructions")
    print()

    # Side-by-side header
    print(f"{'Step':>4}  {'GCC Instruction':<35} {'LLVM Instruction':<35} {'Match':>5}")
    print("-" * 84)

    max_steps = max(len(gcc_insns), len(llvm_insns))
    first_diff = None

    for i in range(max_steps):
        gcc_asm = gcc_insns[i]["asm"] if i < len(gcc_insns) else "---"
        llvm_asm = llvm_insns[i]["asm"] if i < len(llvm_insns) else "---"

        # Compare instruction words if both exist
        gcc_word = gcc_insns[i].get("word") if i < len(gcc_insns) else None
        llvm_word = llvm_insns[i].get("word") if i < len(llvm_insns) else None

        if gcc_word and llvm_word:
            match = "OK" if gcc_word == llvm_word else "DIFF"
        elif gcc_asm == llvm_asm:
            match = "OK"
        else:
            match = "DIFF"

        marker = " <<< FIRST DIVERGENCE" if match == "DIFF" and first_diff is None else ""
        if match == "DIFF" and first_diff is None:
            first_diff = i

        print(f"{i:4d}  {gcc_asm:<35} {llvm_asm:<35} {match:>5}{marker}")

    print()
    if first_diff is not None:
        print(f"DIVERGENCE at step {first_diff}")
        print(f"  GCC:  {gcc_insns[first_diff]['asm'] if first_diff < len(gcc_insns) else 'N/A'}")
        print(f"  LLVM: {llvm_insns[first_diff]['asm'] if first_diff < len(llvm_insns) else 'N/A'}")

        # If we have register state snapshots, show them
        if first_diff < len(gcc_insns) and "regs_after" in gcc_insns[first_diff]:
            print(f"\n  GCC register state after step {first_diff}:")
            for reg, val in gcc_insns[first_diff]["regs_after"].items():
                print(f"    {reg}: {format_fp32_bits(val)}")

        if first_diff < len(llvm_insns) and "regs_after" in llvm_insns[first_diff]:
            print(f"\n  LLVM register state after step {first_diff}:")
            for reg, val in llvm_insns[first_diff]["regs_after"].items():
                print(f"    {reg}: {format_fp32_bits(val)}")

        return 1
    else:
        print("MATCH: Instruction sequences are functionally equivalent")
        print(f"  (GCC: {len(gcc_insns)} insns, LLVM: {len(llvm_insns)} insns)")
        nop_diff = (sum(1 for i in gcc_insns if 'nop' in i.get('asm', '').lower()) -
                    sum(1 for i in llvm_insns if 'nop' in i.get('asm', '').lower()))
        if nop_diff > 0:
            print(f"  LLVM eliminates {nop_diff} NOPs")
        return 0


def main():
    parser = argparse.ArgumentParser(
        description="Side-by-side SFPU instruction trace comparison")
    parser.add_argument("--gcc-sequence", required=True,
                        help="GCC instruction sequence JSON file")
    parser.add_argument("--llvm-sequence", required=True,
                        help="LLVM instruction sequence JSON file")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    gcc_data = load_sequence(args.gcc_sequence)
    llvm_data = load_sequence(args.llvm_sequence)

    failures = compare_traces(gcc_data, llvm_data, args.verbose)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
