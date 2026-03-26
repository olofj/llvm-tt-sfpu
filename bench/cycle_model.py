"""
cycle_model.py — Cycle-accurate SFPU pipeline simulator.

Models the actual cycle count for an instruction sequence on BH and WH,
accounting for:

1. Data dependencies: A 2-cycle instruction (MAD/MUL/ADD/SWAP/LUTFP32)
   produces its result after 2 cycles. If the NEXT instruction reads
   that result, there is a 1-cycle stall.

2. BH hardware scoreboard: Stalls are inserted automatically by hardware.
   The instruction stream has no NOPs, but the *actual* cycle count includes
   stall cycles for dependent reads of 2-cycle producers.

3. WH software NOPs: The compiler inserts explicit SFPNOP instructions.
   These are already in the instruction stream, so cycle count = instruction count
   (each NOP costs 1 cycle).

4. Sub-unit constraints: The SFPU accepts at most 1 instruction per cycle
   regardless of sub-unit. There is no dual-issue.

5. SFPSWAP static delay: Always stalls 1 cycle after, even on BH, regardless
   of dependency (confirmed from GCC rtl-rvtt-schedule.cc).

Reference:
  ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.1 (sub-units, latencies)
  ttsim-analysis/ERRATA.md E-004 (pipeline hazards)
  sfpi-gcc/gcc/config/riscv/tt/rtl-rvtt-schedule.cc (delay types)
  sfpi-gcc/gcc/config/riscv/tt/rvtt.md (xtt_delay attributes)
"""

from dataclasses import dataclass, field
from typing import List, Optional, Set, Tuple
import re


# ============================================================================
# Instruction latencies and sub-unit assignments
# ============================================================================

# Instructions with 2-cycle latency (result available after 2 cycles)
TWO_CYCLE_INSNS = {
    'sfpmad', 'sfpadd', 'sfpmul',
    'sfpmuli', 'sfpaddi',
    'sfpswap', 'sfplutfp32',
    'sfpmul24',
    # SFPSHFT2 is 2-cycle on WH only (for certain modes)
}

# Instructions that always need a static NOP after (even on BH)
STATIC_DELAY_INSNS = {
    'sfpswap',
    # SFPSHFT2 subvec shuffle modes — but we model all SFPSHFT2 as static for safety
}

# Sub-unit assignments
SUBUNIT = {
    'sfpload': 'load', 'sfploadi': 'load', 'sfplut': 'load',
    'sfploadmacro': 'load', 'sfplutfp32': 'mad',
    'sfpmov': 'simple', 'sfpabs': 'simple', 'sfpand': 'simple',
    'sfpor': 'simple', 'sfpnot': 'simple', 'sfpxor': 'simple',
    'sfplz': 'simple', 'sfpshft': 'simple', 'sfpshft2': 'simple',
    'sfpiadd': 'simple', 'sfpsetcc': 'simple', 'sfpdivp2': 'simple',
    'sfpexexp': 'simple', 'sfpexman': 'simple',
    'sfpsetexp': 'simple', 'sfpsetman': 'simple', 'sfpsetsgn': 'simple',
    'sfppushc': 'simple', 'sfppopc': 'simple', 'sfpcompc': 'simple',
    'sfpencc': 'simple', 'sfptransp': 'simple',
    'sfpswap': 'simple', 'sfpconfig': 'simple',
    'sfpgt': 'simple', 'sfple': 'simple',
    'sfparecip': 'simple', 'sfpmov_config': 'simple',
    'sfpmad': 'mad', 'sfpadd': 'mad', 'sfpmul': 'mad',
    'sfpmuli': 'mad', 'sfpaddi': 'mad', 'sfpmul24': 'mad',
    'sfpstochrnd': 'round', 'sfpcast': 'round',
    'sfpstore': 'store',
    'sfpnop': 'none',
}


def parse_instruction(line: str) -> Tuple[str, Optional[str], List[str]]:
    """Parse an instruction line into (opcode, dest_reg, source_regs).

    Format: "SFPMAD\\tL0, L1, L2, L9, 0"
    Returns: ("sfpmad", "L0", ["L1", "L2", "L9"])
    """
    line = line.strip()
    if not line:
        return ('', None, [])

    # Split on tab to get opcode and operands
    parts = line.split('\t', 1)
    opcode = parts[0].strip().lower()

    if len(parts) < 2:
        return (opcode, None, [])

    operands = [o.strip() for o in parts[1].split(',')]

    # Extract register references (L0-L16)
    reg_pattern = re.compile(r'^L(\d+)$', re.IGNORECASE)

    dest_reg = None
    src_regs = []

    for i, op in enumerate(operands):
        m = reg_pattern.match(op)
        if m:
            if i == 0 and opcode not in ('sfpstore', 'sfppushc', 'sfppopc',
                                          'sfpcompc', 'sfpencc', 'sfpsetcc',
                                          'sfpnop', 'sfpconfig'):
                dest_reg = op.upper()
            else:
                src_regs.append(op.upper())
        elif i > 0:
            # Could be an immediate — not a register dependency
            pass

    return (opcode, dest_reg, src_regs)


@dataclass
class CycleResult:
    """Result of cycle simulation for one instruction sequence."""
    total_cycles: int
    stall_cycles: int
    instruction_cycles: int  # = len(insns), each takes 1 issue cycle
    dependency_stalls: List[Tuple[int, str, str]]  # (cycle, producer, consumer)
    static_stalls: List[Tuple[int, str]]  # (cycle, instruction)
    subunit_utilization: dict  # subunit -> count
    instructions_per_cycle: float  # IPC


def simulate_cycles(insns: List[str], bh: bool = True) -> CycleResult:
    """Simulate cycle-accurate execution of an SFPU instruction sequence.

    Args:
        insns: List of assembly instruction strings
        bh: True for Blackhole (hardware scoreboard), False for Wormhole

    Returns:
        CycleResult with detailed cycle breakdown
    """
    cycle = 0
    stall_cycles = 0
    dep_stalls = []
    static_stalls = []
    subunit_counts = {}

    # Track when each register's result will be available
    # reg_ready[reg] = cycle when the value is available for reading
    reg_ready = {}

    # Track the last instruction for static delay
    last_opcode = ''
    last_was_static = False

    for i, insn_line in enumerate(insns):
        opcode, dest_reg, src_regs = parse_instruction(insn_line)

        if not opcode:
            continue

        # Count sub-unit usage
        su = SUBUNIT.get(opcode, 'unknown')
        subunit_counts[su] = subunit_counts.get(su, 0) + 1

        # --- BH: Check for data-dependency stalls ---
        if bh:
            # Check if any source register isn't ready yet
            for src in src_regs:
                ready_at = reg_ready.get(src, 0)
                if ready_at > cycle:
                    stall = ready_at - cycle
                    stall_cycles += stall
                    dep_stalls.append((cycle, src, opcode))
                    cycle = ready_at  # Stall until ready

            # Check static delay from previous instruction
            if last_was_static and opcode != 'sfpnop':
                stall_cycles += 1
                static_stalls.append((cycle, last_opcode))
                cycle += 1

        # --- WH: NOPs are already in the stream, no implicit stalls ---
        # (On WH, the compiler has already inserted NOPs for dependencies.
        #  If it missed one, that's a bug — we don't model it here.)

        # Issue this instruction at current cycle
        issue_cycle = cycle

        # Advance cycle (1 instruction per cycle)
        cycle += 1

        # Update register readiness
        if dest_reg:
            latency = 2 if opcode in TWO_CYCLE_INSNS else 1
            reg_ready[dest_reg] = issue_cycle + latency

        # Track static delay
        last_opcode = opcode
        last_was_static = opcode in STATIC_DELAY_INSNS

    instruction_cycles = len(insns)
    total_cycles = cycle
    ipc = instruction_cycles / total_cycles if total_cycles > 0 else 0

    return CycleResult(
        total_cycles=total_cycles,
        stall_cycles=stall_cycles,
        instruction_cycles=instruction_cycles,
        dependency_stalls=dep_stalls,
        static_stalls=static_stalls,
        subunit_utilization=subunit_counts,
        instructions_per_cycle=round(ipc, 3),
    )


def print_cycle_trace(insns: List[str], bh: bool = True):
    """Print a detailed cycle-by-cycle trace."""
    cycle = 0
    reg_ready = {}
    last_was_static = False
    last_opcode = ''

    print(f"{'Cyc':>4s}  {'Stall':>5s}  {'Instruction':<45s}  {'Notes'}")
    print("-" * 85)

    for insn_line in insns:
        opcode, dest_reg, src_regs = parse_instruction(insn_line)
        if not opcode:
            continue

        notes = []

        if bh:
            # Check dependency stalls
            for src in src_regs:
                ready_at = reg_ready.get(src, 0)
                if ready_at > cycle:
                    stall = ready_at - cycle
                    notes.append(f"STALL {stall}c waiting for {src}")
                    cycle = ready_at

            if last_was_static and opcode != 'sfpnop':
                notes.append(f"STATIC STALL after {last_opcode}")
                cycle += 1

        issue_cycle = cycle
        cycle += 1

        if dest_reg:
            latency = 2 if opcode in TWO_CYCLE_INSNS else 1
            reg_ready[dest_reg] = issue_cycle + latency
            if latency > 1:
                notes.append(f"{dest_reg} ready@{issue_cycle + latency}")

        stall_str = "STALL" if notes else ""
        notes_str = "; ".join(notes)
        print(f"{issue_cycle:4d}  {stall_str:>5s}  {insn_line:<45s}  {notes_str}")

        last_opcode = opcode
        last_was_static = opcode in STATIC_DELAY_INSNS

    print(f"\nTotal: {cycle} cycles ({cycle - len(insns)} stall cycles)")


# ============================================================================
# Convenience functions for benchmarks
# ============================================================================

def compare_cycles(gcc_insns: List[str], llvm_insns: List[str],
                   name: str = "") -> dict:
    """Compare cycle counts between GCC and LLVM sequences."""
    gcc_bh = simulate_cycles(gcc_insns, bh=True)
    gcc_wh = simulate_cycles(gcc_insns, bh=False)
    llvm_bh = simulate_cycles(llvm_insns, bh=True)
    llvm_wh = simulate_cycles(llvm_insns, bh=False)

    return {
        "name": name,
        "gcc": {
            "instructions": len(gcc_insns),
            "bh_cycles": gcc_bh.total_cycles,
            "bh_stalls": gcc_bh.stall_cycles,
            "bh_ipc": gcc_bh.instructions_per_cycle,
            "wh_cycles": gcc_wh.total_cycles,
        },
        "llvm": {
            "instructions": len(llvm_insns),
            "bh_cycles": llvm_bh.total_cycles,
            "bh_stalls": llvm_bh.stall_cycles,
            "bh_ipc": llvm_bh.instructions_per_cycle,
            "wh_cycles": llvm_wh.total_cycles,
        },
        "delta": {
            "bh_cycles_saved": gcc_bh.total_cycles - llvm_bh.total_cycles,
            "bh_cycle_reduction_pct": round(
                (gcc_bh.total_cycles - llvm_bh.total_cycles) / gcc_bh.total_cycles * 100, 1
            ) if gcc_bh.total_cycles > 0 else 0,
            "wh_cycles_saved": gcc_wh.total_cycles - llvm_wh.total_cycles,
            "wh_cycle_reduction_pct": round(
                (gcc_wh.total_cycles - llvm_wh.total_cycles) / gcc_wh.total_cycles * 100, 1
            ) if gcc_wh.total_cycles > 0 else 0,
        },
    }
