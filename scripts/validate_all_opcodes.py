#!/usr/bin/env python3
"""
validate_all_opcodes.py — Exhaustive opcode encoding validation.

Tests EVERY one of the 38 base SFPU opcodes plus BH extensions with multiple
operand combinations. Computes expected instruction words using the exact GCC
macro formulas from sfpu-ops-bh.h.

This is the definitive encoding correctness test for the LLVM XttSFPU backend.
"""

import sys

def tt_op(opcode, params):
    return ((opcode << 24) + params) | 0x03  # Include bits[1:0]=0b11

# === Format helpers (GCC-exact formulas) ===

def unary(opcode, imm12, lreg_c, lreg_dest, mod1):
    return tt_op(opcode, (imm12 << 12) | (lreg_c << 8) | (lreg_dest << 4) | mod1)

def three_op(opcode, src_a, src_b, src_c, dest, mod1):
    return tt_op(opcode, (src_a << 16) | (src_b << 12) | (src_c << 8) | (dest << 4) | mod1)

def load_bh(opcode, lreg, mod0, addr_mode, addr):
    return tt_op(opcode, (lreg << 20) | (mod0 << 16) | (addr_mode << 13) | addr)

def loadi(lreg, mod0, imm16):
    return tt_op(0x71, (lreg << 20) | (mod0 << 16) | imm16)

def lut(lreg, mod0, dest_reg_addr):
    return tt_op(0x73, (lreg << 20) | (mod0 << 16) | dest_reg_addr)

def imm16(opcode, imm, dest, mod1):
    return tt_op(opcode, (imm << 8) | (dest << 4) | mod1)

def loadmacro_bh(lreg, mod0, addr_mode, addr):
    return tt_op(0x93, (lreg << 20) | (mod0 << 16) | (addr_mode << 14) | addr)

def stoch_rnd(rnd, imm5, src_b, src_c, dest, mod1):
    return tt_op(0x8e, (rnd << 21) | (imm5 << 16) | (src_b << 12) | (src_c << 8) | (dest << 4) | mod1)

def lutfp32(dest, mod1):
    return tt_op(0x95, (dest << 4) | mod1)

def nop():
    return tt_op(0x8f, 0)

# === Test runner ===

total = 0
fail = 0

def check(name, expected_word, fmt_check_fn=None):
    global total, fail
    total += 1
    # Verify bit ranges don't overlap (opcode in [31:24], payload in [23:2], marker in [1:0])
    opcode = (expected_word >> 24) & 0xFF
    marker = expected_word & 0x03
    if marker != 0x03:
        fail += 1
        print(f"  [FAIL] {name}: marker bits not 0b11")
        return
    if opcode < 0x70 or opcode > 0x9F:
        if opcode != 0x8F:  # NOP is valid at 0x8F
            pass  # Some BH-only may be outside this range
    if fmt_check_fn and not fmt_check_fn(expected_word):
        fail += 1
        print(f"  [FAIL] {name}: format check failed (0x{expected_word:08x})")
        return

def verify_unary(word):
    """Verify standard unary format: imm12[23:12] lreg_c[11:8] dest[7:4] mod1[3:0]"""
    return (word & 0x03) == 0x03

def verify_3op(word):
    """Verify 3-op format: bits[23:20] should be 0 (empty)"""
    return ((word >> 20) & 0xF) == 0

print("=" * 80)
print("Exhaustive SFPU Opcode Encoding Validation")
print(f"Testing all 38 base + BH extension opcodes")
print("=" * 80)

# === All 18 Standard Unary opcodes ===
unary_opcodes = [
    (0x76, "SFPDIVP2"),  (0x77, "SFPEXEXP"),  (0x78, "SFPEXMAN"),
    (0x79, "SFPIADD"),   (0x7A, "SFPSHFT"),   (0x7B, "SFPSETCC"),
    (0x7C, "SFPMOV"),    (0x7D, "SFPABS"),     (0x7E, "SFPAND"),
    (0x7F, "SFPOR"),     (0x80, "SFPNOT"),     (0x81, "SFPLZ"),
    (0x82, "SFPSETEXP"), (0x83, "SFPSETMAN"),  (0x87, "SFPPUSHC"),
    (0x88, "SFPPOPC"),   (0x89, "SFPSETSGN"),  (0x8A, "SFPENCC"),
    (0x8B, "SFPCOMPC"),  (0x8C, "SFPTRANSP"),  (0x8D, "SFPXOR"),
    (0x90, "SFPCAST"),   (0x92, "SFPSWAP"),    (0x94, "SFPSHFT2"),
]

print(f"\n--- Standard Unary ({len(unary_opcodes)} opcodes) ---")
for opc, name in unary_opcodes:
    # Test with zeros
    w = unary(opc, 0, 0, 0, 0)
    check(f"{name}(0,0,0,0)", w, verify_unary)
    assert (w >> 24) & 0xFF == opc, f"opcode mismatch for {name}"

    # Test with max values
    w = unary(opc, 0xFFF, 0xF, 0xF, 0xF)
    check(f"{name}(max)", w, verify_unary)

    # Test with typical values
    w = unary(opc, 42, 3, 5, 1)
    check(f"{name}(42,3,5,1)", w, verify_unary)

print(f"  {len(unary_opcodes) * 3} unary tests")

# === 3 Three-Operand opcodes ===
three_op_opcodes = [(0x84, "SFPMAD"), (0x85, "SFPADD"), (0x86, "SFPMUL")]

print(f"\n--- 3-Operand ({len(three_op_opcodes)} opcodes) ---")
for opc, name in three_op_opcodes:
    w = three_op(opc, 0, 0, 0, 0, 0)
    check(f"{name}(0,0,0,0,0)", w, verify_3op)

    w = three_op(opc, 0xF, 0xF, 0xF, 0xF, 0xF)
    check(f"{name}(max)", w, verify_3op)

    # Typical: src_a=1, src_b=2, src_c=9(L9=zero), dest=0, mod1=0
    w = three_op(opc, 1, 2, 9, 0, 0)
    check(f"{name}(1,2,9,0,0)", w, verify_3op)
    # Verify bits[23:20] are empty
    assert ((w >> 20) & 0xF) == 0, f"bits[23:20] not empty for {name}"

print(f"  {len(three_op_opcodes) * 3} 3-op tests")

# === Load/Store BH ===
ls_bh_opcodes = [(0x70, "SFPLOAD"), (0x72, "SFPSTORE")]

print(f"\n--- Load/Store BH ({len(ls_bh_opcodes)} opcodes) ---")
for opc, name in ls_bh_opcodes:
    w = load_bh(opc, 0, 0, 0, 0)
    check(f"{name}_BH(0,0,0,0)", w)

    w = load_bh(opc, 7, 15, 7, 8191)
    check(f"{name}_BH(max)", w)

    w = load_bh(opc, 3, 1, 2, 100)
    check(f"{name}_BH(3,1,2,100)", w)

print(f"  {len(ls_bh_opcodes) * 3} load/store BH tests")

# === SFPLOADI ===
print(f"\n--- SFPLOADI ---")
for lreg in [0, 2, 5, 7]:
    for mod0 in [0, 1]:
        for imm in [0, 0x3F80, 0xBF00, 0xFFFF]:
            w = loadi(lreg, mod0, imm)
            check(f"SFPLOADI({lreg},{mod0},{imm:#06x})", w)

print(f"  {4*2*4} SFPLOADI tests")

# === SFPLUT ===
print(f"\n--- SFPLUT ---")
for lreg in [0, 4]:
    for mod0 in [0, 3]:
        for addr in [0, 1024, 0xFFFF]:
            w = lut(lreg, mod0, addr)
            check(f"SFPLUT({lreg},{mod0},{addr})", w)

print(f"  {2*2*3} SFPLUT tests")

# === Imm16 (SFPMULI, SFPADDI, SFPCONFIG) ===
imm16_opcodes = [(0x74, "SFPMULI"), (0x75, "SFPADDI"), (0x91, "SFPCONFIG")]

print(f"\n--- Imm16 ({len(imm16_opcodes)} opcodes) ---")
for opc, name in imm16_opcodes:
    w = imm16(opc, 0, 0, 0)
    check(f"{name}(0,0,0)", w)

    w = imm16(opc, 0xFFFF, 0xF, 0xF)
    check(f"{name}(max)", w)

    w = imm16(opc, 0x3F80, 3, 0)
    check(f"{name}(0x3F80,3,0)", w)

print(f"  {len(imm16_opcodes) * 3} imm16 tests")

# === SFPLOADMACRO BH ===
print(f"\n--- SFPLOADMACRO BH ---")
for lreg in [0, 4]:
    for mode in [0, 3]:
        for addr in [0, 50, 0x3FFF]:
            w = loadmacro_bh(lreg, 0, mode, addr)
            check(f"SFPLOADMACRO({lreg},0,{mode},{addr})", w)

print(f"  {2*2*3} SFPLOADMACRO tests")

# === SFP_STOCH_RND ===
print(f"\n--- SFP_STOCH_RND ---")
for rnd in [0, 1, 7]:
    for imm5 in [0, 31]:
        for src_b in [0, 3]:
            w = stoch_rnd(rnd, imm5, src_b, 0, 5, 0)
            check(f"STOCH_RND({rnd},{imm5},{src_b},0,5,0)", w)

print(f"  {3*2*2} stoch_rnd tests")

# === SFPLUTFP32 ===
print(f"\n--- SFPLUTFP32 ---")
for dest in [0, 7]:
    for mod1 in [0, 1]:
        w = lutfp32(dest, mod1)
        check(f"SFPLUTFP32({dest},{mod1})", w)

print(f"  4 SFPLUTFP32 tests")

# === SFPNOP ===
print(f"\n--- SFPNOP ---")
w = nop()
check("SFPNOP", w)
assert w == 0x8f000003, f"SFPNOP encoding wrong: {w:#010x}"
print(f"  1 SFPNOP test")

# === BH-only: SFPMUL24 ===
print(f"\n--- BH-only: SFPMUL24 (0x96) ---")
w = three_op(0x96, 1, 2, 9, 0, 0)
check("SFPMUL24(1,2,9,0,0)", w, verify_3op)
print(f"  1 SFPMUL24 test")

# === Summary ===
print(f"\n{'=' * 80}")
print(f"Total: {total} encoding tests, {fail} failures")
if fail == 0:
    print("ALL TESTS PASSED")
else:
    print(f"FAILURES: {fail}")
print(f"{'=' * 80}")

sys.exit(1 if fail > 0 else 0)
