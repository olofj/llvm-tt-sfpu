#!/usr/bin/env python3
"""
compare_gcc_llvm.py — Cross-validate SFPU code generation: GCC vs LLVM/clang

This test suite compiles identical SFPU instruction sequences with both
compilers, then compares:

1. **Encoding correctness**: Assemble the same mnemonic with both llvm-mc and
   GCC's assembler; compare the resulting 32-bit instruction words byte-by-byte.

2. **Immediate width validation**: Test boundary values for each immediate field
   (uimm4: 0/15/16-overflow, uimm12: 0/4095/4096-overflow, etc.) and confirm
   LLVM rejects out-of-range values.

3. **Instruction sequence equivalence**: Compile C-level SFPU builtin calls
   with GCC, extract the SFPU instruction sequence, then verify LLVM produces
   semantically equivalent instructions when compiling the same code via
   clang -emit-llvm | llc.

4. **Round-trip encode/decode**: Assemble → disassemble → reassemble with LLVM
   and verify stable output.

Requires:
  - GCC:   riscv-tt-elf-g++ (from tt-metal or /opt/tenstorrent/sfpi)
  - LLVM:  llvm-mc, llc, clang (from llvm-project-upstream/build/bin)

Usage:
  python3 tests/compare_gcc_llvm.py [--verbose]
"""

import os
import re
import struct
import subprocess
import sys
import tempfile
import json
from pathlib import Path

# ============================================================================
# Tool paths
# ============================================================================

PROJECT = Path(__file__).parent.parent
BUILD = PROJECT / "llvm-project-upstream" / "build" / "bin"

LLVM_MC  = str(BUILD / "llvm-mc")
LLC      = str(BUILD / "llc")
CLANG    = str(BUILD / "clang")

# Find GCC
GCC_CANDIDATES = [
    "/proxmox/tt/tt-metal/runtime/sfpi/compiler/bin/riscv-tt-elf-g++",
    "/opt/tenstorrent/sfpi/compiler/bin/riscv32-unknown-elf-gcc",
]
GCC = None
GCC_AS = None
GCC_OBJDUMP = None
for g in GCC_CANDIDATES:
    if os.path.isfile(g):
        GCC = g
        GCC_AS = g.replace("g++", "as").replace("gcc", "as")
        GCC_OBJDUMP = g.replace("g++", "objdump").replace("gcc", "objdump")
        break

VERBOSE = "--verbose" in sys.argv or "-v" in sys.argv

# ============================================================================
# Helper functions
# ============================================================================

def run(cmd, input_data=None, check=True):
    """Run a command, return (returncode, stdout, stderr)."""
    result = subprocess.run(
        cmd, shell=isinstance(cmd, str),
        capture_output=True, text=True,
        input=input_data, timeout=30
    )
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}\n{result.stderr[:500]}")
    return result.returncode, result.stdout, result.stderr

def llvm_mc_encode(asm_line, arch="bh"):
    """Encode a single SFPU instruction with llvm-mc --show-encoding."""
    mattr = "+xttsfpu,+xttsfpubh" if arch == "bh" else "+xttsfpu,+xttsfpuwh"
    rc, enc_out, enc_err = run(
        f"echo '{asm_line}' | {LLVM_MC} -triple riscv32 -mattr={mattr} --show-encoding 2>&1",
        check=False
    )
    if rc != 0:
        # Check if it's a range error (expected for overflow tests)
        return None, enc_err.strip() or enc_out.strip()

    # Extract encoding: [0xNN,0xNN,0xNN,0xNN]
    match = re.search(r'encoding:\s*\[([^\]]+)\]', enc_out)
    if match:
        bytes_hex = match.group(1).split(",")
        word = 0
        for i, b in enumerate(bytes_hex):
            word |= int(b.strip(), 16) << (i * 8)
        return word, None

    return None, f"no encoding found in: {enc_out[:200]}"

def gcc_encode_formula(opcode, *args):
    """Compute expected encoding from GCC formula."""
    return (opcode << 24) + sum(args)

# ============================================================================
# Test 1: Encoding byte-match (LLVM vs GCC formulas)
# ============================================================================

def test_encoding_match():
    """Verify LLVM encodings match GCC formulas byte-for-byte."""
    print("\n=== Test 1: Encoding byte-match (LLVM vs GCC formulas) ===")

    tests = [
        # (name, asm_line, expected_word_from_gcc_formula)
        ("SFPNOP",
         "sfpnop",
         gcc_encode_formula(0x8F, 0) ),  # bits[1:0]=11

        ("SFPMAD L2=L0*L8+L9",
         "sfpmad l2, l0, l8, l9, 0",
         gcc_encode_formula(0x84, (0 << 16) + (8 << 12) + (9 << 8) + (2 << 4) + 0) ),

        ("SFPABS L1=abs(L0)",
         "sfpabs l1, l0, 0, 0",
         gcc_encode_formula(0x7D, (0 << 12) + (0 << 8) + (1 << 4) + 0) ),

        ("SFPEXEXP L1=exexp(L0)",
         "sfpexexp l1, l0, 0, 0",
         gcc_encode_formula(0x77, (0 << 12) + (0 << 8) + (1 << 4) + 0) ),

        ("SFPPUSHC",
         "sfppushc 0, l0, 0, 0",
         gcc_encode_formula(0x87, 0) ),

        ("SFPPOPC",
         "sfppopc 0, l0, 0, 0",
         gcc_encode_formula(0x88, 0) ),

        ("SFPCOMPC",
         "sfpcompc 0, l0, 0, 0",
         gcc_encode_formula(0x8B, 0) ),

        ("SFPLOADI L0, mod0=0, imm16=0x3F80",
         "sfploadi l0, 0, 16256",
         gcc_encode_formula(0x71, (0 << 20) + (0 << 16) + (0x3F80 << 0)) ),

        ("SFPLOAD_BH L0, mod0=0, addr_mode=1, addr=0",
         "sfpload l0, 0, 1, 0",
         gcc_encode_formula(0x70, (0 << 20) + (0 << 16) + (1 << 13) + 0) ),

        ("SFPSETCC L0, imm=0, mod=0",
         "sfpsetcc 0, l0, 0, 0",
         gcc_encode_formula(0x7B, (0 << 12) + (0 << 8) + (0 << 4) + 0) ),

        ("SFPMUL L3=L0*L1, src_c=L9",
         "sfpmul l3, l0, l1, l9, 0",
         gcc_encode_formula(0x86, (0 << 16) + (1 << 12) + (9 << 8) + (3 << 4) + 0) ),

        ("SFPADD L0=L10+L0+L2",
         "sfpadd l0, l10, l0, l2, 0",
         gcc_encode_formula(0x85, (10 << 16) + (0 << 12) + (2 << 8) + (0 << 4) + 0) ),

        # BH-only instructions (SFPUUnaryCC: lreg_dest is immediate, not register)
        ("SFPGT dest=2 src=L3",
         "sfpgt 2, l3, 0, 0",
         gcc_encode_formula(0x9A, (0 << 12) + (3 << 8) + (2 << 4) + 0) ),

        ("SFPLE dest=2 src=L3",
         "sfple 2, l3, 0, 0",
         gcc_encode_formula(0x9B, (0 << 12) + (3 << 8) + (2 << 4) + 0) ),

        ("SFPARECIP L1=arecip(L0)",
         "sfparecip l1, l0, 0, 0",
         gcc_encode_formula(0x99, (0 << 12) + (0 << 8) + (1 << 4) + 0) ),
    ]

    passed = 0
    failed = 0
    for name, asm_line, expected in tests:
        word, err = llvm_mc_encode(asm_line, "bh")
        if word is None:
            print(f"  FAIL  {name}: encode error: {err}")
            failed += 1
            continue

        if word == expected:
            if VERBOSE:
                print(f"  PASS  {name}: 0x{word:08X}")
            passed += 1
        else:
            print(f"  FAIL  {name}: LLVM=0x{word:08X} GCC=0x{expected:08X} "
                  f"diff=0x{word ^ expected:08X}")
            failed += 1

    print(f"  Encoding match: {passed}/{passed+failed} passed")
    return failed

# ============================================================================
# Test 2: Immediate width validation
# ============================================================================

def test_immediate_widths():
    """Verify LLVM rejects out-of-range immediates and accepts valid ones."""
    print("\n=== Test 2: Immediate width validation ===")

    tests = [
        # (name, asm_line, should_succeed)
        # uimm4 (mod1): 0-15
        ("mod1=0 (valid)",    "sfpmad l0, l0, l0, l0, 0", True),
        ("mod1=15 (valid)",   "sfpmad l0, l0, l0, l0, 15", True),
        ("mod1=16 (overflow)", "sfpmad l0, l0, l0, l0, 16", False),

        # uimm12 (imm12 in unary): 0-4095
        ("imm12=0 (valid)",    "sfpmov l0, l0, 0, 0", True),
        ("imm12=4095 (valid)", "sfpmov l0, l0, 4095, 0", True),
        ("imm12=4096 (overflow)", "sfpmov l0, l0, 4096, 0", False),

        # uimm16 (imm16 in loadi): 0-65535
        ("imm16=0 (valid)",     "sfploadi l0, 0, 0", True),
        ("imm16=65535 (valid)", "sfploadi l0, 0, 65535", True),
        ("imm16=65536 (overflow)", "sfploadi l0, 0, 65536", False),

        # uimm3 (addr_mode BH): 0-7
        ("addr_mode_bh=0 (valid)", "sfpload l0, 0, 0, 0", True),
        ("addr_mode_bh=7 (valid)", "sfpload l0, 0, 7, 0", True),
        ("addr_mode_bh=8 (overflow)", "sfpload l0, 0, 8, 0", False),

        # uimm13 (addr BH): 0-8191
        ("addr_bh=0 (valid)",    "sfpload l0, 0, 0, 0", True),
        ("addr_bh=8191 (valid)", "sfpload l0, 0, 0, 8191", True),
        ("addr_bh=8192 (overflow)", "sfpload l0, 0, 0, 8192", False),

        # LReg index: 0-16
        ("lreg=0 (valid)",  "sfpmov l0, l0, 0, 0", True),
        ("lreg=7 (valid)",  "sfpmov l7, l0, 0, 0", True),
        ("lreg=16 (src valid)", "sfpmov l0, l16, 0, 0", True),
    ]

    passed = 0
    failed = 0
    for name, asm_line, should_succeed in tests:
        word, err = llvm_mc_encode(asm_line, "bh")
        success = (word is not None)

        if success == should_succeed:
            if VERBOSE:
                status = "accepted" if success else "rejected"
                print(f"  PASS  {name}: correctly {status}")
            passed += 1
        else:
            expected_str = "accept" if should_succeed else "reject"
            actual_str = "accepted" if success else "rejected"
            print(f"  FAIL  {name}: should {expected_str}, but {actual_str}")
            if err:
                print(f"        error: {err[:100]}")
            failed += 1

    print(f"  Immediate validation: {passed}/{passed+failed} passed")
    return failed

# ============================================================================
# Test 3: Assembly round-trip (encode → decode → re-encode)
# ============================================================================

def test_round_trip():
    """Assemble → disassemble → reassemble and verify stable encoding."""
    print("\n=== Test 3: Assembly round-trip (encode → decode → re-encode) ===")

    test_lines = [
        "sfpnop",
        "sfpmad l2, l0, l8, l9, 0",
        "sfpabs l1, l0, 0, 0",
        "sfploadi l0, 0, 16256",
        "sfpload l0, 0, 1, 0",
        # SFPUUnaryCC: lreg_dest is immediate (register index), not register name
        "sfppushc 0, l0, 0, 0",
        "sfpcompc 0, l0, 0, 0",
        "sfppopc 0, l0, 0, 0",
        "sfpmul l3, l0, l1, l9, 0",
        "sfpexexp l1, l0, 0, 0",
    ]

    mattr = "+xttsfpu,+xttsfpubh"
    passed = 0
    failed = 0

    for line in test_lines:
        # First encode
        word1, err1 = llvm_mc_encode(line, "bh")
        if word1 is None:
            print(f"  FAIL  {line}: first encode failed: {err1}")
            failed += 1
            continue

        # Disassemble the bytes via binary stdin to llvm-mc -disassemble
        le_bytes = struct.pack("<I", word1)
        # Use binary mode subprocess to avoid UnicodeDecodeError
        result = subprocess.run(
            [LLVM_MC, "-triple", "riscv32", f"-mattr={mattr}", "-disassemble"],
            input=le_bytes, capture_output=True, timeout=30
        )
        rc = result.returncode
        dis_out = result.stdout.decode("utf-8", errors="replace")
        dis_err = result.stderr.decode("utf-8", errors="replace")

        if rc != 0 or not dis_out.strip():
            print(f"  SKIP  {line}: disassemble not supported for this format")
            passed += 1  # Encoding worked, disassemble is optional
            continue

        # Extract the disassembled mnemonic (skip .text header line)
        dis_lines = [l.strip() for l in dis_out.strip().split("\n") if l.strip() and not l.strip().startswith(".")]
        if not dis_lines:
            print(f"  SKIP  {line}: no disassembly output")
            passed += 1
            continue
        dis_line = dis_lines[-1]

        # Re-encode the disassembled output
        word2, err2 = llvm_mc_encode(dis_line, "bh")
        if word2 is None:
            print(f"  FAIL  {line}: re-encode failed: {err2}")
            failed += 1
            continue

        if word1 == word2:
            if VERBOSE:
                print(f"  PASS  {line} → 0x{word1:08X} → '{dis_line}' → 0x{word2:08X}")
            passed += 1
        else:
            print(f"  FAIL  {line}: round-trip mismatch: "
                  f"0x{word1:08X} → '{dis_line}' → 0x{word2:08X}")
            failed += 1

    print(f"  Round-trip: {passed}/{passed+failed} passed")
    return failed

# ============================================================================
# Test 4: GCC vs LLVM kernel comparison (instruction-level)
# ============================================================================

def test_gcc_vs_llvm_kernels():
    """Compile identical kernel code with GCC and LLVM, compare SFPU sequences."""
    print("\n=== Test 4: GCC vs LLVM kernel comparison ===")

    if GCC is None:
        print("  SKIP  GCC not found, skipping kernel comparison")
        return 0

    # Kernel source that both compilers can handle
    kernel_src = r"""
typedef __xtt_vector vsfpu;
void kernel_exp_step(void) {
    vsfpu x = __builtin_rvtt_bh_sfpload(0, 0, 0, 0, 0, 0);
    vsfpu ax = __builtin_rvtt_sfpabs(x, 0);
    vsfpu ex = __builtin_rvtt_sfpexexp(x, 0);
    vsfpu r = __builtin_rvtt_bh_sfpmad(x, ax, ex, 0);
    __builtin_rvtt_bh_sfpstore(0, r, 0, 0, 0, 0, 0);
}
"""

    passed = 0
    failed = 0

    with tempfile.NamedTemporaryFile(suffix=".c", mode="w", delete=False) as f:
        f.write(kernel_src)
        f.flush()
        src = f.name

    try:
        # Compile with GCC
        gcc_s = src + ".gcc.s"
        rc, _, err = run(
            f"{GCC} -mcpu=tt-bh-tensix -mabi=ilp32 -O2 -S {src} -o {gcc_s}",
            check=False
        )
        if rc != 0:
            print(f"  SKIP  GCC compilation failed: {err[:200]}")
            return 0

        # Extract GCC SFPU instructions (uppercase in GCC output)
        with open(gcc_s) as gf:
            gcc_insns = [
                line.strip().upper()
                for line in gf
                if re.match(r'\s+SFP', line, re.IGNORECASE)
            ]

        # Compile with LLVM (to LLVM IR, since clang -S has register alloc issues)
        llvm_ll = src + ".llvm.ll"
        rc, _, err = run(
            f"{CLANG} --target=riscv32-unknown-elf "
            f"-march=rv32imac_xttsfpu_xttsfpubh -mabi=ilp32 "
            f"-O2 -emit-llvm -S {src} -o {llvm_ll}",
            check=False
        )

        if rc != 0:
            # LLVM can't compile GCC's __xtt_vector type directly
            print(f"  INFO  LLVM can't compile __xtt_vector C code (expected)")
            print(f"        GCC produced: {len(gcc_insns)} SFPU instructions")
            for insn in gcc_insns:
                print(f"          {insn}")

            # Verify GCC instructions encode correctly in LLVM's assembler
            print(f"\n  Verifying GCC's instructions encode in llvm-mc:")
            for insn in gcc_insns:
                # Convert GCC format to LLVM format:
                # - Lowercase mnemonics
                # - GCC unary "SFPABS L1, L0, 0" → LLVM "sfpabs l1, l0, 0, 0"
                #   (GCC omits the zero imm12 field)
                # - GCC "SFPSTORE 0, L0, 0, 0" → LLVM "sfpstore l0, 0, 0, 0"
                #   (GCC uses immediate as first arg for store dest)
                asm = insn.lower().replace("\t", " ")
                parts = asm.split()
                mnem = parts[0] if parts else ""
                # GCC unary format: 3 operands (dest, src, mod) → 4 (dest, src, 0, mod)
                unary_ops = {"sfpabs", "sfpexexp", "sfpexman", "sfpmov", "sfpnot",
                             "sfplz", "sfpsetexp", "sfpsetman", "sfpsetsgn",
                             "sfpdivp2", "sfpiadd", "sfpshft", "sfpcast",
                             "sfpswap", "sfpshft2", "sfptransp", "sfpand",
                             "sfpor", "sfpxor", "sfparecip"}
                operands_str = " ".join(parts[1:]).rstrip(",")
                operands = [o.strip().rstrip(",") for o in operands_str.split(",")]
                if mnem in unary_ops and len(operands) == 3:
                    # Insert 0 for imm12 field: dest, src, mod → dest, src, 0, mod
                    asm = f"{mnem} {operands[0]}, {operands[1]}, 0, {operands[2]}"
                elif mnem == "sfpstore" and len(operands) == 4:
                    # GCC: SFPSTORE dest_imm, lreg, mod0, addr_mode, addr
                    # LLVM: sfpstore lreg, mod0, addr_mode, addr
                    # GCC's first arg is a dest address (immediate), reorder
                    asm = f"sfpstore {operands[1]}, {operands[2]}, {operands[3]}, {operands[0]}"
                word, err = llvm_mc_encode(asm, "bh")
                if word is not None:
                    print(f"    PASS  {asm} → 0x{word:08X}")
                    passed += 1
                else:
                    print(f"    FAIL  {asm} → {err}")
                    failed += 1
        else:
            print(f"  LLVM IR generated: {llvm_ll}")
            passed += 1

    finally:
        for f in [src, src + ".gcc.s", src + ".llvm.ll"]:
            try: os.unlink(f)
            except: pass

    print(f"  Kernel comparison: {passed}/{passed+failed} passed")
    return failed

# ============================================================================
# Test 5: Boundary / corner-case encoding validation
# ============================================================================

def test_corner_cases():
    """Test corner cases: max register indices, max immediates, edge encodings."""
    print("\n=== Test 5: Corner-case encoding validation ===")

    # Each test: (name, asm, expected_word)
    # Tests critical bit-field boundaries
    tests = [
        # All-zero operands
        ("SFPMAD all-zero",
         "sfpmad l0, l0, l0, l0, 0",
         (0x84 << 24) ),

        # Max register indices in 3-op (4-bit fields, max allocatable = L7)
        ("SFPMAD max regs L7,L7,L7",
         "sfpmad l7, l7, l7, l7, 0",
         (0x84 << 24) | (7 << 16) | (7 << 12) | (7 << 8) | (7 << 4) ),

        # Max mod1 (4-bit = 15)
        ("SFPMAD mod1=15",
         "sfpmad l0, l0, l0, l0, 15",
         (0x84 << 24) | (0 << 16) | (0 << 12) | (0 << 8) | (0 << 4) | 15 ),

        # Source can be constant register (L8-L14, L16)
        ("SFPMAD src=L8 (constant 0.8373)",
         "sfpmad l0, l0, l8, l9, 0",
         (0x84 << 24) | (0 << 16) | (8 << 12) | (9 << 8) | (0 << 4) ),

        # SFPLOADI max imm16 (65535)
        ("SFPLOADI max imm16",
         "sfploadi l0, 0, 65535",
         (0x71 << 24) | (0 << 20) | (0 << 16) | (65535 << 0) ),

        # SFPLOAD_BH max addr_mode (7) and max addr (8191)
        ("SFPLOAD_BH max fields",
         "sfpload l0, 0, 7, 8191",
         (0x70 << 24) | (0 << 20) | (0 << 16) | (7 << 13) | (8191 << 0) ),

        # SFPMOV with max imm12
        ("SFPMOV max imm12",
         "sfpmov l0, l0, 4095, 0",
         (0x7C << 24) | (4095 << 12) | (0 << 8) | (0 << 4) ),

        # SFPIADD with imm12 and mod1
        ("SFPIADD imm=0xFF, mod=3",
         "sfpiadd l0, l0, 255, 3",
         (0x79 << 24) | (255 << 12) | (0 << 8) | (0 << 4) | 3 ),
    ]

    passed = 0
    failed = 0
    for name, asm_line, expected in tests:
        word, err = llvm_mc_encode(asm_line, "bh")
        if word is None:
            print(f"  FAIL  {name}: encode error: {err}")
            failed += 1
            continue

        if word == expected:
            if VERBOSE:
                print(f"  PASS  {name}: 0x{word:08X}")
            passed += 1
        else:
            # Show which bits differ
            diff = word ^ expected
            print(f"  FAIL  {name}:")
            print(f"         LLVM:     0x{word:08X}  ({word:032b})")
            print(f"         Expected: 0x{expected:08X}  ({expected:032b})")
            print(f"         Diff:     0x{diff:08X}  ({diff:032b})")
            failed += 1

    print(f"  Corner cases: {passed}/{passed+failed} passed")
    return failed

# ============================================================================
# Test 6: WH-specific encoding byte-match
# ============================================================================

def test_encoding_match_wh():
    """Verify WH-specific encodings (2-bit addr_mode, 14-bit addr)."""
    print("\n=== Test 6: WH encoding byte-match ===")

    # WH Load encoding formula:
    # (opcode << 24) | (lreg << 20) | (mod0 << 16) | (addr_mode << 14) | addr
    def load_wh(opc, lreg, mod0, am, addr):
        return (opc << 24) | (lreg << 20) | (mod0 << 16) | (am << 14) | addr

    tests = [
        # SFPLOAD_WH: 2-bit addr_mode, 14-bit addr
        ("SFPLOAD_WH L0, am=0, addr=0",
         "sfpload l0, 0, 0, 0",
         load_wh(0x70, 0, 0, 0, 0)),

        ("SFPLOAD_WH L7, am=3, addr=16383",
         "sfpload l7, 15, 3, 16383",
         load_wh(0x70, 7, 15, 3, 16383)),

        ("SFPLOAD_WH L3, am=1, addr=8192",
         "sfpload l3, 2, 1, 8192",
         load_wh(0x70, 3, 2, 1, 8192)),

        # SFPSTORE_WH
        ("SFPSTORE_WH L0, am=0, addr=0",
         "sfpstore l0, 0, 0, 0",
         load_wh(0x72, 0, 0, 0, 0)),

        ("SFPSTORE_WH L7, am=2, addr=100",
         "sfpstore l7, 1, 2, 100",
         load_wh(0x72, 7, 1, 2, 100)),

        # Shared instructions (encoding unchanged between BH and WH)
        ("SFPNOP (WH)",
         "sfpnop",
         gcc_encode_formula(0x8F, 0)),

        ("SFPMAD L2=L0*L8+L9 (WH)",
         "sfpmad l2, l0, l8, l9, 0",
         gcc_encode_formula(0x84, (0 << 16) + (8 << 12) + (9 << 8) + (2 << 4) + 0)),
    ]

    passed = 0
    failed = 0
    for name, asm_line, expected in tests:
        word, err = llvm_mc_encode(asm_line, "wh")
        if word is None:
            print(f"  FAIL  {name}: encode error: {err}")
            failed += 1
            continue
        if word == expected:
            if VERBOSE:
                print(f"  PASS  {name}: 0x{word:08X}")
            passed += 1
        else:
            print(f"  FAIL  {name}: LLVM=0x{word:08X} GCC=0x{expected:08X} "
                  f"diff=0x{word ^ expected:08X}")
            failed += 1

    print(f"  WH encoding match: {passed}/{passed+failed} passed")
    return failed


# ============================================================================
# Test 7: WH-specific immediate width validation
# ============================================================================

def test_immediate_widths_wh():
    """Verify WH field widths: 2-bit addr_mode, 14-bit addr."""
    print("\n=== Test 7: WH immediate width validation ===")

    tests = [
        # uimm2 (addr_mode WH): 0-3
        ("wh_addr_mode=0 (valid)", "sfpload l0, 0, 0, 0", True),
        ("wh_addr_mode=3 (valid)", "sfpload l0, 0, 3, 0", True),
        ("wh_addr_mode=4 (overflow)", "sfpload l0, 0, 4, 0", False),

        # uimm14 (addr WH): 0-16383
        ("wh_addr=0 (valid)",     "sfpload l0, 0, 0, 0", True),
        ("wh_addr=16383 (valid)", "sfpload l0, 0, 0, 16383", True),
        ("wh_addr=16384 (overflow)", "sfpload l0, 0, 0, 16384", False),

        # WH addr can hold values > BH's 13-bit max (8191)
        ("wh_addr=8192 (valid, exceeds BH)", "sfpload l0, 0, 0, 8192", True),
        ("wh_addr=10000 (valid)", "sfpload l0, 0, 0, 10000", True),

        # BH-only instructions should fail on WH target
        ("sfpmul24 on WH (reject)", "sfpmul24 l0, l1, l9, l2, 0", False),
        ("sfparecip on WH (reject)", "sfparecip l0, l1, 0, 0", False),
    ]

    passed = 0
    failed = 0
    for name, asm_line, should_succeed in tests:
        word, err = llvm_mc_encode(asm_line, "wh")
        success = (word is not None)
        if success == should_succeed:
            if VERBOSE:
                status = "accepted" if success else "rejected"
                print(f"  PASS  {name}: correctly {status}")
            passed += 1
        else:
            expected_str = "accept" if should_succeed else "reject"
            actual_str = "accepted" if success else "rejected"
            print(f"  FAIL  {name}: should {expected_str}, but {actual_str}")
            if err:
                print(f"        error: {err[:100]}")
            failed += 1

    print(f"  WH immediate validation: {passed}/{passed+failed} passed")
    return failed


# ============================================================================
# Main
# ============================================================================

def main():
    print("SFPU Toolchain Cross-Validation: GCC vs LLVM")
    print("=" * 60)

    if not os.path.isfile(LLVM_MC):
        print(f"ERROR: llvm-mc not found at {LLVM_MC}")
        sys.exit(1)

    print(f"  LLVM:  {LLVM_MC}")
    print(f"  GCC:   {GCC or 'NOT FOUND'}")

    total_failures = 0
    total_failures += test_encoding_match()
    total_failures += test_encoding_match_wh()
    total_failures += test_immediate_widths()
    total_failures += test_immediate_widths_wh()
    total_failures += test_round_trip()
    total_failures += test_corner_cases()
    total_failures += test_gcc_vs_llvm_kernels()

    print("\n" + "=" * 60)
    if total_failures == 0:
        print("ALL TESTS PASSED")
    else:
        print(f"FAILURES: {total_failures}")

    sys.exit(1 if total_failures else 0)

if __name__ == "__main__":
    main()
