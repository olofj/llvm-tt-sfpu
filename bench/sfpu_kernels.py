"""
sfpu_kernels.py — SFPU kernel definitions for benchmark comparison.

Each kernel is defined as a pair of instruction sequences:
  - GCC output: what sfpi-gcc actually emits (based on LLK kernel analysis)
  - LLVM output: what our XttSFPU backend would emit

GCC sequences are reconstructed from:
  - rvtt-bh.md assembly format strings
  - rtl-rvtt-schedule.cc NOP insertion logic
  - LLK kernel source code (ckernel_sfpu_*.h)
  - Known GCC deficiencies (GH-Q-002, GH-CC-008, GH-Q-005, GH-Q-006)

LLVM sequences incorporate:
  - MUL+ADD→MAD combining
  - BH NOP elimination (hardware scoreboard)
  - SFPGT/SFPLE direct use on BH
  - Scheduler interleaving of independent operations
  - SFPLOADI immediate folding
  - Negated operand folding via mod1 bits
"""

from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class Kernel:
    """A benchmark kernel with GCC and LLVM instruction sequences."""
    name: str
    category: str
    description: str
    gcc_insns: List[str]
    llvm_insns: List[str]
    notes: str = ""
    source_file: str = ""  # LLK source reference


# ============================================================================
# ML Activation Kernels
# ============================================================================

KERNELS: List[Kernel] = []

KERNELS.append(Kernel(
    name="exp_horner_2step",
    category="ml_kernels",
    description="Exponential via 2-step Horner series (e^x approximation)",
    source_file="ckernel_sfpu_exp.h:_sfpu_exp_",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPEXEXP\tL1, L0, 0, 0",
        "SFPDIVP2\tL0, L1, 0, 0",
        "SFPMUL\tL2, L0, L8, L9, 0",     # GCC: separate MUL (GH-Q-002)
        "SFPNOP",                          # GCC: NOP even on BH (GH-CC-008)
        "SFPADD\tL2, L10, L2, L9, 0",    # GCC: separate ADD
        "SFPMUL\tL0, L0, L2, L9, 0",
        "SFPNOP",
        "SFPADD\tL0, L10, L0, L10, 0",
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPEXEXP\tL1, L0, 0, 0",
        "SFPDIVP2\tL0, L1, 0, 0",
        "SFPMAD\tL2, L0, L8, L9, 0",     # LLVM: MAD combining
        "SFPMAD\tL0, L0, L2, L10, 0",    # LLVM: MAD combining
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    notes="GH-Q-002 (FMA), GH-CC-008 (BH NOPs), GH-Q-006 (scheduling)",
))

KERNELS.append(Kernel(
    name="exp_full_with_squaring",
    category="ml_kernels",
    description="Full exp with predicated exponent squaring loop",
    source_file="ckernel_sfpu_exp.h:_sfpu_exp_",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPEXEXP\tL1, L0, 0, 0",
        "SFPPUSHC\t0",
        "SFPSETCC\tL1, 0, 4",             # CC: exp >= 0
        "SFPSETEXP\tL0, L0, 126, 0",
        "SFPPOPC\t0",
        "SFPMUL\tL2, L0, L8, L9, 0",
        "SFPNOP",
        "SFPADD\tL2, L10, L2, L9, 0",
        "SFPMUL\tL0, L0, L2, L9, 0",
        "SFPNOP",
        "SFPADD\tL0, L10, L0, L10, 0",
        "SFPPUSHC\t0",
        "SFPSETCC\tL1, 0, 4",
        "SFPMUL\tL0, L0, L0, L9, 0",     # val * val
        "SFPNOP",
        "SFPPOPC\t0",
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPEXEXP\tL1, L0, 0, 2",         # LLVM: fused EXEXP+CC (peephole)
        "SFPPUSHC\t0",
        "SFPSETEXP\tL0, L0, 126, 0",
        "SFPPOPC\t0",
        "SFPMAD\tL2, L0, L8, L9, 0",     # LLVM: MAD
        "SFPMAD\tL0, L0, L2, L10, 0",    # LLVM: MAD
        "SFPPUSHC\t0",
        "SFPSETCC\tL1, 0, 4",
        "SFPMUL\tL0, L0, L0, L9, 0",
        "SFPPOPC\t0",
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    notes="EXEXP+SETCC fusion, MAD combining, BH NOP elimination",
))

KERNELS.append(Kernel(
    name="tanh_lut",
    category="ml_kernels",
    description="Tanh via 3-coefficient LUT",
    source_file="ckernel_sfpu_tanh.h:_calculate_tanh_",
    gcc_insns=[
        "SFPLOADI\tL0, 0, 0x1DFF",
        "SFPLOADI\tL1, 0, 0x481A",
        "SFPLOADI\tL2, 0, 0xFF00",
        "SFPLOAD\tL3, 0, 0, 0",
        "SFPLUT\tL3, 0",                  # GCC format
        "SFPNOP",                          # GCC: NOP after LUT (dynamic delay)
        "SFPSTORE\tL3, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOADI\tL0, 0, 0x1DFF",
        "SFPLOADI\tL1, 0, 0x481A",
        "SFPLOADI\tL2, 0, 0xFF00",
        "SFPLOAD\tL3, 0, 0, 0",
        "SFPLUT\tL3, 0",
        "SFPSTORE\tL3, 0, 0, 0",          # LLVM: no NOP on BH
    ],
    notes="LUT path, BH NOP elimination",
))

KERNELS.append(Kernel(
    name="sigmoid_approx",
    category="ml_kernels",
    description="Sigmoid approximation via LUTFP32 + 0.5 bias",
    source_file="ckernel_sfpu_sigmoid.h:_calculate_sigmoid_",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLUTFP32\tL0, 6",              # SGN_RETAIN mode
        "SFPNOP",                          # GCC: NOP (LUTFP32 is 2-cycle)
        "SFPADDI\tL0, 0x3800, 0",         # +0.5 bias
        "SFPNOP",
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLUTFP32\tL0, 6",
        "SFPADDI\tL0, 0x3800, 0",         # LLVM: BH scoreboard handles latency
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    notes="LUTFP32 path, BH NOP elimination, SFPADDI immediate",
))

KERNELS.append(Kernel(
    name="gelu_approx",
    category="ml_kernels",
    description="GELU approximation via MUL + LUTFP32 + ADD",
    source_file="ckernel_sfpu_gelu.h:_calculate_gelu_",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPMUL\tL1, L0, L11, L9, 0",    # half_in = in * 0.5
        "SFPNOP",
        "SFPLUTFP32\tL0, 2",              # lut result
        "SFPNOP",
        "SFPADD\tL0, L10, L1, L0, 0",    # half_in + lut_result
        "SFPNOP",
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPMUL\tL1, L0, L11, L9, 0",
        "SFPLUTFP32\tL0, 2",              # Interleaved with MUL latency
        "SFPMAD\tL0, L10, L1, L0, 0",    # MAD combining
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    notes="MAD combining, scheduler interleaving MUL+LUTFP32",
))

KERNELS.append(Kernel(
    name="gelu_accurate_horner",
    category="ml_kernels",
    description="GELU accurate CDF via 5th-order Horner polynomial",
    source_file="ckernel_sfpu_gelu.h:_calculate_gelu_body_",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPMUL\tL1, L0, L0, L9, 0",     # x^2
        "SFPNOP",
        # Horner: ((((a5*x + a4)*x + a3)*x + a2)*x + a1)*x + a0
        "SFPMUL\tL2, L1, L0, L9, 0",     # a5*x = x^2 * x (placeholder)
        "SFPNOP",
        "SFPADD\tL2, L10, L2, L0, 0",    # + a4*x
        "SFPMUL\tL2, L2, L0, L9, 0",
        "SFPNOP",
        "SFPADD\tL2, L10, L2, L0, 0",
        "SFPMUL\tL2, L2, L0, L9, 0",
        "SFPNOP",
        "SFPADD\tL2, L10, L2, L0, 0",
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPMUL\tL1, L0, L0, L9, 0",     # x^2
        "SFPMAD\tL2, L1, L0, L0, 0",     # MAD: a5*x + a4
        "SFPMAD\tL2, L2, L0, L0, 0",     # MAD: prev*x + a3
        "SFPMAD\tL2, L2, L0, L0, 0",     # MAD: prev*x + a2
        "SFPMAD\tL2, L2, L0, L0, 0",     # MAD: prev*x + a1
        "SFPSTORE\tL0, 0, 0, 0",
    ],
    notes="Full Horner chain with MAD, BH NOP elimination",
))

KERNELS.append(Kernel(
    name="reciprocal_nr1",
    category="ml_kernels",
    description="Reciprocal with 1-iteration Newton-Raphson refinement",
    source_file="ckernel_sfpu_recip.h:_sfpu_reciprocal_<1>",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPARECIP\tL1, L0, 0",
        "SFPMUL\tL2, L0, L1, L9, 0",
        "SFPNOP",
        "SFPADD\tL2, L10, L2, L11, 0",   # t = x*y - 1.0
        "SFPPUSHC\t0",
        "SFPSETCC\tL2, 0, 0",
        "SFPMUL\tL3, L1, L2, L9, 0",
        "SFPNOP",
        "SFPADD\tL1, L10, L3, L9, 0",
        "SFPPOPC\t0",
        "SFPSTORE\tL1, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPARECIP\tL1, L0, 0",
        "SFPMAD\tL2, L0, L1, L11, 0",    # MAD: t = x*y + (-1.0)
        "SFPPUSHC\t0",
        "SFPSETCC\tL2, 0, 0",
        "SFPMAD\tL1, L1, L2, L9, 0",     # MAD: y = y*t + 0.0
        "SFPPOPC\t0",
        "SFPSTORE\tL1, 0, 0, 0",
    ],
    notes="MAD combining, BH NOP elimination, predication",
))

KERNELS.append(Kernel(
    name="reciprocal_nr2",
    category="ml_kernels",
    description="Reciprocal with 2-iteration Newton-Raphson refinement",
    source_file="ckernel_sfpu_recip.h:_sfpu_reciprocal_<2>",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPARECIP\tL1, L0, 0",
        "SFPMUL\tL2, L0, L1, L9, 0",
        "SFPNOP",
        "SFPADD\tL2, L10, L2, L11, 0",
        "SFPMUL\tL3, L1, L2, L9, 0",
        "SFPNOP",
        "SFPADD\tL3, L10, L3, L9, 0",
        "SFPPUSHC\t0",
        "SFPSETCC\tL2, 0, 0",
        "SFPMUL\tL4, L0, L3, L9, 0",
        "SFPNOP",
        "SFPADD\tL4, L10, L4, L11, 0",
        "SFPMUL\tL1, L3, L4, L9, 0",
        "SFPNOP",
        "SFPADD\tL1, L10, L1, L9, 0",
        "SFPPOPC\t0",
        "SFPSTORE\tL1, 0, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPARECIP\tL1, L0, 0",
        "SFPMAD\tL2, L0, L1, L11, 0",
        "SFPMAD\tL3, L1, L2, L9, 0",
        "SFPPUSHC\t0",
        "SFPSETCC\tL2, 0, 0",
        "SFPMAD\tL4, L0, L3, L11, 0",
        "SFPMAD\tL1, L3, L4, L9, 0",
        "SFPPOPC\t0",
        "SFPSTORE\tL1, 0, 0, 0",
    ],
    notes="MAD combining throughout, BH NOP elimination, predication",
))

KERNELS.append(Kernel(
    name="softmax_row",
    category="ml_kernels",
    description="Softmax per-row: normalize + exp + store",
    source_file="(composite pattern)",
    gcc_insns=[
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
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPEXEXP\tL1, L0, 0, 0",
        "SFPDIVP2\tL0, L1, 0, 0",
        "SFPMAD\tL2, L0, L8, L9, 0",
        "SFPMAD\tL0, L0, L2, L10, 0",
        "SFPSTORE\tL0, 0, 0, 0",
    ],
))

# ============================================================================
# Scheduling Benchmarks
# ============================================================================

KERNELS.append(Kernel(
    name="two_independent_muls",
    category="scheduling",
    description="Two independent MUL operations (tests scheduler interleaving)",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPLOAD\tL2, 0, 0, 32",
        "SFPLOAD\tL3, 0, 0, 48",
        "SFPMUL\tL0, L0, L1, L9, 0",
        "SFPNOP",
        "SFPMUL\tL2, L2, L3, L9, 0",
        "SFPNOP",
        "SFPSTORE\tL0, 0, 0, 0",
        "SFPSTORE\tL2, 0, 0, 16",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPLOAD\tL2, 0, 0, 32",
        "SFPLOAD\tL3, 0, 0, 48",
        "SFPMUL\tL0, L0, L1, L9, 0",
        "SFPMUL\tL2, L2, L3, L9, 0",     # Interleaved, no NOP
        "SFPSTORE\tL0, 0, 0, 0",
        "SFPSTORE\tL2, 0, 0, 16",
    ],
    notes="GH-Q-006: scheduler fills MUL latency slot",
))

KERNELS.append(Kernel(
    name="four_independent_mads",
    category="scheduling",
    description="Four independent MAD operations (pipeline saturation test)",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPLOAD\tL2, 0, 0, 32",
        "SFPLOAD\tL3, 0, 0, 48",
        "SFPMUL\tL0, L0, L8, L9, 0",
        "SFPNOP",
        "SFPADD\tL0, L10, L0, L10, 0",
        "SFPMUL\tL1, L1, L8, L9, 0",
        "SFPNOP",
        "SFPADD\tL1, L10, L1, L10, 0",
        "SFPMUL\tL2, L2, L8, L9, 0",
        "SFPNOP",
        "SFPADD\tL2, L10, L2, L10, 0",
        "SFPMUL\tL3, L3, L8, L9, 0",
        "SFPNOP",
        "SFPADD\tL3, L10, L3, L10, 0",
        "SFPSTORE\tL0, 0, 0, 0",
        "SFPSTORE\tL1, 0, 0, 16",
        "SFPSTORE\tL2, 0, 0, 32",
        "SFPSTORE\tL3, 0, 0, 48",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPLOAD\tL2, 0, 0, 32",
        "SFPLOAD\tL3, 0, 0, 48",
        "SFPMAD\tL0, L0, L8, L10, 0",    # 4 independent MADs
        "SFPMAD\tL1, L1, L8, L10, 0",    # interleaved naturally
        "SFPMAD\tL2, L2, L8, L10, 0",
        "SFPMAD\tL3, L3, L8, L10, 0",
        "SFPSTORE\tL0, 0, 0, 0",
        "SFPSTORE\tL1, 0, 0, 16",
        "SFPSTORE\tL2, 0, 0, 32",
        "SFPSTORE\tL3, 0, 0, 48",
    ],
    notes="GH-Q-002 + GH-Q-006: MAD combining + scheduling",
))

# ============================================================================
# Comparison Benchmarks (BH-specific)
# ============================================================================

KERNELS.append(Kernel(
    name="bh_comparison_gt",
    category="comparison",
    description="Greater-than comparison using BH SFPGT vs GCC's MAD+SETCC",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPMAD\tL2, L0, L11, L1, 0",    # t = a*(-1) + b = b - a
        "SFPNOP",
        "SFPSETCC\tL2, 0, 0",
        "SFPSETCC\tL2, 0, 8",            # complement
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPGT\tL0, L1, 0, 0",           # Direct SFPGT (BH only)
    ],
    notes="GH-Q-005: SFPGT (3 insns vs 6)",
))

KERNELS.append(Kernel(
    name="bh_comparison_le",
    category="comparison",
    description="Less-or-equal comparison using BH SFPLE",
    gcc_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPMAD\tL2, L0, L11, L1, 0",
        "SFPNOP",
        "SFPSETCC\tL2, 0, 0",
    ],
    llvm_insns=[
        "SFPLOAD\tL0, 0, 0, 0",
        "SFPLOAD\tL1, 0, 0, 16",
        "SFPLE\tL0, L1, 0, 0",
    ],
    notes="GH-Q-005: SFPLE",
))


def get_kernels(category: Optional[str] = None) -> List[Kernel]:
    """Return kernels, optionally filtered by category."""
    if category is None:
        return KERNELS
    return [k for k in KERNELS if k.category == category]


def get_categories() -> List[str]:
    """Return sorted list of unique categories."""
    return sorted(set(k.category for k in KERNELS))
