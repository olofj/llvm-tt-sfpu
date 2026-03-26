#!/usr/bin/env python3
"""
run_benchmarks.py — SFPU benchmark runner with JUnit XML + JSON output.

Compares GCC (sfpi-gcc) and LLVM (XttSFPU) codegen for SFPU kernels.
Produces machine-readable output for CI dashboards and metrics tracking.

Usage:
  ./bench/run_benchmarks.py                           # Console + both formats
  ./bench/run_benchmarks.py --format=junit            # JUnit XML only
  ./bench/run_benchmarks.py --format=json             # JSON only
  ./bench/run_benchmarks.py --category=ml_kernels     # Filter by category
  ./bench/run_benchmarks.py --output=results/         # Output directory
"""

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional
from xml.etree.ElementTree import Element, SubElement, tostring, indent

# Add bench/ to path
sys.path.insert(0, os.path.dirname(__file__))
from sfpu_kernels import Kernel, get_kernels, get_categories
from cycle_model import simulate_cycles

# ============================================================================
# SFPU Cycle Model
# ============================================================================

LATENCY = {
    'sfpload': 1, 'sfploadi': 1, 'sfpstore': 1, 'sfplut': 1,
    'sfpmov': 1, 'sfpabs': 1, 'sfpand': 1, 'sfpor': 1,
    'sfpnot': 1, 'sfpxor': 1, 'sfplz': 1, 'sfpshft': 1,
    'sfpiadd': 1, 'sfpsetcc': 1, 'sfpdivp2': 1, 'sfpexexp': 1,
    'sfpexman': 1, 'sfpsetexp': 1, 'sfpsetman': 1, 'sfpsetsgn': 1,
    'sfppushc': 1, 'sfppopc': 1, 'sfpcompc': 1, 'sfpencc': 1,
    'sfptransp': 1, 'sfpcast': 1, 'sfpconfig': 1, 'sfpshft2': 1,
    'sfpstochrnd': 1,
    'sfpmad': 2, 'sfpadd': 2, 'sfpmul': 2,
    'sfpmuli': 2, 'sfpaddi': 2,
    'sfpswap': 2, 'sfplutfp32': 2,
    'sfpmul24': 2, 'sfparecip': 1,
    'sfpgt': 1, 'sfple': 1,
    'sfpnop': 1, 'sfploadmacro': 1,
}


@dataclass
class KernelMetrics:
    """Metrics for a single kernel's instruction sequence."""
    name: str
    compiler: str
    total_instructions: int
    nop_count: int
    mad_count: int
    mul_count: int
    add_count: int
    load_count: int
    store_count: int
    cc_stack_ops: int  # pushc + popc + compc
    estimated_cycles_bh: int
    estimated_cycles_wh: int
    code_size_bytes: int
    unique_opcodes: int


def analyze_sequence(name: str, compiler: str, insns: List[str]) -> KernelMetrics:
    """Analyze an instruction sequence and compute metrics."""
    nops = 0
    mads = 0
    muls = 0
    adds = 0
    loads = 0
    stores = 0
    cc_ops = 0
    opcodes = set()
    wh_cycles = 0

    for insn in insns:
        op = insn.split('\t')[0].strip().lower()
        opcodes.add(op)

        if op == 'sfpnop':
            nops += 1
        elif op == 'sfpmad':
            mads += 1
        elif op.startswith('sfpmul') and op != 'sfpmuli':
            muls += 1
        elif op.startswith('sfpadd') and op != 'sfpaddi':
            adds += 1
        elif op in ('sfpload', 'sfploadi', 'sfplut', 'sfplutfp32', 'sfploadmacro'):
            loads += 1
        elif op == 'sfpstore':
            stores += 1
        elif op in ('sfppushc', 'sfppopc', 'sfpcompc'):
            cc_ops += 1

        wh_cycles += LATENCY.get(op, 1)

    # Use the cycle-accurate model for BH and WH
    bh_sim = simulate_cycles(insns, bh=True)
    wh_sim = simulate_cycles(insns, bh=False)

    return KernelMetrics(
        name=name,
        compiler=compiler,
        total_instructions=len(insns),
        nop_count=nops,
        mad_count=mads,
        mul_count=muls,
        add_count=adds,
        load_count=loads,
        store_count=stores,
        cc_stack_ops=cc_ops,
        estimated_cycles_bh=bh_sim.total_cycles,  # Cycle-accurate with stalls
        estimated_cycles_wh=wh_sim.total_cycles,   # Cycle-accurate for WH
        code_size_bytes=len(insns) * 4,
        unique_opcodes=len(opcodes),
    )


@dataclass
class BenchmarkResult:
    """Result for a single kernel benchmark."""
    kernel_name: str
    category: str
    description: str
    gcc_metrics: KernelMetrics
    llvm_metrics: KernelMetrics
    instruction_reduction: int
    instruction_reduction_pct: float
    nop_elimination: int
    mad_gain: int
    cycle_reduction_bh: int
    cycle_reduction_bh_pct: float
    passed: bool
    notes: str


def run_benchmark(kernel: Kernel) -> BenchmarkResult:
    """Run a single kernel benchmark."""
    gcc = analyze_sequence(kernel.name, "gcc", kernel.gcc_insns)
    llvm = analyze_sequence(kernel.name, "llvm", kernel.llvm_insns)

    insn_reduction = gcc.total_instructions - llvm.total_instructions
    insn_pct = (insn_reduction / gcc.total_instructions * 100) if gcc.total_instructions > 0 else 0
    nop_elim = gcc.nop_count - llvm.nop_count
    mad_gain = llvm.mad_count - gcc.mad_count
    cycle_red = gcc.estimated_cycles_bh - llvm.estimated_cycles_bh
    cycle_pct = (cycle_red / gcc.estimated_cycles_bh * 100) if gcc.estimated_cycles_bh > 0 else 0

    # A benchmark "passes" if LLVM is at least as good as GCC
    passed = llvm.total_instructions <= gcc.total_instructions

    return BenchmarkResult(
        kernel_name=kernel.name,
        category=kernel.category,
        description=kernel.description,
        gcc_metrics=gcc,
        llvm_metrics=llvm,
        instruction_reduction=insn_reduction,
        instruction_reduction_pct=insn_pct,
        nop_elimination=nop_elim,
        mad_gain=mad_gain,
        cycle_reduction_bh=cycle_red,
        cycle_reduction_bh_pct=cycle_pct,
        passed=passed,
        notes=kernel.notes,
    )


# ============================================================================
# Output Formatters
# ============================================================================

def format_console(results: List[BenchmarkResult]) -> str:
    """Human-readable console output."""
    lines = []
    lines.append("=" * 95)
    lines.append("SFPU Codegen Benchmark: GCC (sfpi-gcc) vs LLVM (XttSFPU) — BH Target")
    lines.append(f"Date: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    lines.append("=" * 95)

    by_category = {}
    for r in results:
        by_category.setdefault(r.category, []).append(r)

    total_gcc = total_llvm = total_nops_gcc = total_nops_llvm = 0

    total_gcc_cyc = total_llvm_cyc = 0

    for cat in sorted(by_category):
        lines.append(f"\n--- {cat} ---")
        lines.append(f"  {'Kernel':<26s} {'--- Instructions ---':>22s}  {'--- BH Cycles ---':>20s}  {'NOPs':>5s}")
        lines.append(f"  {'':26s} {'GCC':>6s} {'LLVM':>6s} {'Save':>5s} {'%':>4s}  {'GCC':>6s} {'LLVM':>6s} {'Save':>5s} {'%':>4s}  {'elim':>5s}")

        for r in by_category[cat]:
            status = "OK" if r.passed else "!!"
            cyc_save = r.gcc_metrics.estimated_cycles_bh - r.llvm_metrics.estimated_cycles_bh
            cyc_pct = (cyc_save / r.gcc_metrics.estimated_cycles_bh * 100) if r.gcc_metrics.estimated_cycles_bh > 0 else 0
            lines.append(
                f"  [{status}] {r.kernel_name:<22s} "
                f"{r.gcc_metrics.total_instructions:6d} "
                f"{r.llvm_metrics.total_instructions:6d} "
                f"{r.instruction_reduction:+5d} "
                f"{r.instruction_reduction_pct:3.0f}%  "
                f"{r.gcc_metrics.estimated_cycles_bh:6d} "
                f"{r.llvm_metrics.estimated_cycles_bh:6d} "
                f"{cyc_save:+5d} "
                f"{cyc_pct:3.0f}%  "
                f"{r.nop_elimination:+5d}"
            )
            total_gcc += r.gcc_metrics.total_instructions
            total_llvm += r.llvm_metrics.total_instructions
            total_nops_gcc += r.gcc_metrics.nop_count
            total_nops_llvm += r.llvm_metrics.nop_count
            total_gcc_cyc += r.gcc_metrics.estimated_cycles_bh
            total_llvm_cyc += r.llvm_metrics.estimated_cycles_bh

    total_save = total_gcc - total_llvm
    total_pct = (total_save / total_gcc * 100) if total_gcc > 0 else 0
    cyc_save = total_gcc_cyc - total_llvm_cyc
    cyc_pct = (cyc_save / total_gcc_cyc * 100) if total_gcc_cyc > 0 else 0
    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed

    lines.append(f"\n{'=' * 100}")
    lines.append(f"TOTALS ({len(results)} kernels, {passed} passed, {failed} regressions):")
    lines.append(f"  Instructions: GCC {total_gcc:4d} → LLVM {total_llvm:4d}  ({total_save:+d}, {total_pct:.1f}% reduction)")
    lines.append(f"  BH Cycles:    GCC {total_gcc_cyc:4d} → LLVM {total_llvm_cyc:4d}  ({cyc_save:+d}, {cyc_pct:.1f}% reduction)")
    lines.append(f"  NOPs:         GCC {total_nops_gcc:4d} → LLVM {total_nops_llvm:4d}  ({total_nops_gcc - total_nops_llvm} eliminated)")
    lines.append(f"{'=' * 100}")

    return "\n".join(lines)


def format_junit_xml(results: List[BenchmarkResult]) -> str:
    """JUnit XML output for CI integration."""
    testsuites = Element("testsuites")
    testsuites.set("name", "SFPU Codegen Benchmarks")
    testsuites.set("timestamp", datetime.now(timezone.utc).isoformat())

    by_category = {}
    for r in results:
        by_category.setdefault(r.category, []).append(r)

    total_tests = len(results)
    total_failures = sum(1 for r in results if not r.passed)

    testsuites.set("tests", str(total_tests))
    testsuites.set("failures", str(total_failures))

    for cat in sorted(by_category):
        suite = SubElement(testsuites, "testsuite")
        suite.set("name", f"sfpu.{cat}")
        cat_results = by_category[cat]
        suite.set("tests", str(len(cat_results)))
        suite.set("failures", str(sum(1 for r in cat_results if not r.passed)))
        suite.set("timestamp", datetime.now(timezone.utc).isoformat())

        for r in cat_results:
            tc = SubElement(suite, "testcase")
            tc.set("name", r.kernel_name)
            tc.set("classname", f"sfpu.{cat}")
            tc.set("time", "0")  # Static analysis, no runtime

            # Store metrics as properties
            props = SubElement(tc, "properties")
            for key, val in [
                ("gcc_instructions", r.gcc_metrics.total_instructions),
                ("llvm_instructions", r.llvm_metrics.total_instructions),
                ("instruction_reduction", r.instruction_reduction),
                ("instruction_reduction_pct", f"{r.instruction_reduction_pct:.1f}"),
                ("gcc_nops", r.gcc_metrics.nop_count),
                ("llvm_nops", r.llvm_metrics.nop_count),
                ("nop_elimination", r.nop_elimination),
                ("mad_gain", r.mad_gain),
                ("gcc_cycles_bh", r.gcc_metrics.estimated_cycles_bh),
                ("llvm_cycles_bh", r.llvm_metrics.estimated_cycles_bh),
                ("cycle_reduction_bh_pct", f"{r.cycle_reduction_bh_pct:.1f}"),
                ("gcc_code_bytes", r.gcc_metrics.code_size_bytes),
                ("llvm_code_bytes", r.llvm_metrics.code_size_bytes),
            ]:
                prop = SubElement(props, "property")
                prop.set("name", str(key))
                prop.set("value", str(val))

            if not r.passed:
                failure = SubElement(tc, "failure")
                failure.set("message", f"LLVM regression: {r.llvm_metrics.total_instructions} insns > {r.gcc_metrics.total_instructions} GCC insns")
                failure.text = r.notes

            # System-out with description
            stdout = SubElement(tc, "system-out")
            stdout.text = f"{r.description}\n{r.notes}"

    indent(testsuites, space="  ")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + tostring(testsuites, encoding="unicode")


def format_json_metrics(results: List[BenchmarkResult]) -> str:
    """JSON metrics for time-series tracking."""
    total_gcc = sum(r.gcc_metrics.total_instructions for r in results)
    total_llvm = sum(r.llvm_metrics.total_instructions for r in results)
    total_nops_gcc = sum(r.gcc_metrics.nop_count for r in results)
    total_nops_llvm = sum(r.llvm_metrics.nop_count for r in results)

    data = {
        "metadata": {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "backend": "XttSFPU",
            "target": "tensix-bh",
            "llvm_version": "19.1.0",
            "gcc_baseline": "sfpi-gcc (2026-03)",
        },
        "summary": {
            "total_kernels": len(results),
            "passed": sum(1 for r in results if r.passed),
            "failed": sum(1 for r in results if not r.passed),
            "total_gcc_instructions": total_gcc,
            "total_llvm_instructions": total_llvm,
            "instruction_reduction_pct": round((total_gcc - total_llvm) / total_gcc * 100, 1) if total_gcc else 0,
            "total_gcc_nops": total_nops_gcc,
            "total_llvm_nops": total_nops_llvm,
            "nops_eliminated": total_nops_gcc - total_nops_llvm,
        },
        "kernels": [
            {
                "name": r.kernel_name,
                "category": r.category,
                "passed": r.passed,
                "gcc": asdict(r.gcc_metrics),
                "llvm": asdict(r.llvm_metrics),
                "delta": {
                    "instruction_reduction": r.instruction_reduction,
                    "instruction_reduction_pct": round(r.instruction_reduction_pct, 1),
                    "nop_elimination": r.nop_elimination,
                    "mad_gain": r.mad_gain,
                    "cycle_reduction_bh": r.cycle_reduction_bh,
                    "cycle_reduction_bh_pct": round(r.cycle_reduction_bh_pct, 1),
                },
            }
            for r in results
        ],
    }

    return json.dumps(data, indent=2)


# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="SFPU codegen benchmark runner")
    parser.add_argument("--format", choices=["console", "junit", "json", "all"],
                        default="all", help="Output format (default: all)")
    parser.add_argument("--category", help="Filter by kernel category")
    parser.add_argument("--output", default=".", help="Output directory")
    parser.add_argument("--list-categories", action="store_true",
                        help="List available categories and exit")
    args = parser.parse_args()

    if args.list_categories:
        for cat in get_categories():
            kernels = get_kernels(cat)
            print(f"  {cat}: {len(kernels)} kernels")
        return

    # Run benchmarks
    kernels = get_kernels(args.category)
    if not kernels:
        print(f"No kernels found for category '{args.category}'", file=sys.stderr)
        sys.exit(1)

    results = [run_benchmark(k) for k in kernels]

    # Create output directory
    outdir = Path(args.output)
    outdir.mkdir(parents=True, exist_ok=True)

    # Produce outputs
    if args.format in ("console", "all"):
        print(format_console(results))

    if args.format in ("junit", "all"):
        junit_path = outdir / "sfpu_bench.xml"
        junit_path.write_text(format_junit_xml(results))
        print(f"JUnit XML: {junit_path}", file=sys.stderr)

    if args.format in ("json", "all"):
        json_path = outdir / "metrics.json"
        json_path.write_text(format_json_metrics(results))
        print(f"JSON metrics: {json_path}", file=sys.stderr)

    # Exit with failure if any regression
    failures = sum(1 for r in results if not r.passed)
    sys.exit(1 if failures > 0 else 0)


if __name__ == "__main__":
    main()
