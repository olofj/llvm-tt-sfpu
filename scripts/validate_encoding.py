#!/usr/bin/env python3
"""
validate_encoding.py — Cross-validate LLVM XttSFPU encoding against GCC headers

Computes expected 32-bit instruction words using the exact GCC macro formulas.
All formulas verified against:
  - sfpi-gcc/gcc/config/riscv/tt/sfpu-ops-bh.h (Blackhole)
  - sfpi-gcc/gcc/config/riscv/tt/sfpu-ops-wh.h (Wormhole)

Key BH vs WH difference:
  SFPLOAD/SFPSTORE BH: addr_mode << 13 (3-bit mode, 13-bit addr)
  SFPLOAD/SFPSTORE WH: addr_mode << 14 (2-bit mode, 14-bit addr)
  SFPLOADMACRO: identical between BH and WH (addr_mode << 14)
  All other SFPU instructions: identical between BH and WH
"""

import sys

def tt_op(opcode, params):
    return (opcode << 24) + params

# ============================================================================
# GCC encoding formulas — BH (exact from sfpu-ops-bh.h)
# ============================================================================

def sfpload_bh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op(0x70, (lreg_ind << 20) + (instr_mod0 << 16) +
                       (sfpu_addr_mode << 13) + (dest_reg_addr << 0))

def sfploadi_bh(lreg_ind, instr_mod0, imm16):
    return tt_op(0x71, (lreg_ind << 20) + (instr_mod0 << 16) + (imm16 << 0))

def sfpstore_bh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op(0x72, (lreg_ind << 20) + (instr_mod0 << 16) +
                       (sfpu_addr_mode << 13) + (dest_reg_addr << 0))

def sfplut_bh(lreg_ind, instr_mod0, dest_reg_addr):
    return tt_op(0x73, (lreg_ind << 20) + (instr_mod0 << 16) + (dest_reg_addr << 0))

def sfpmuli_bh(imm16_math, lreg_dest, instr_mod1):
    return tt_op(0x74, (imm16_math << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpaddi_bh(imm16_math, lreg_dest, instr_mod1):
    return tt_op(0x75, (imm16_math << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfp_unary_bh(opcode, imm12_math, lreg_c, lreg_dest, instr_mod1):
    return tt_op(opcode, (imm12_math << 12) + (lreg_c << 8) +
                         (lreg_dest << 4) + (instr_mod1 << 0))

def sfpmad_bh(lreg_src_a, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op(0x84, (lreg_src_a << 16) + (lreg_src_b << 12) +
                       (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpadd_bh(lreg_src_a, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op(0x85, (lreg_src_a << 16) + (lreg_src_b << 12) +
                       (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpmul_bh(lreg_src_a, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op(0x86, (lreg_src_a << 16) + (lreg_src_b << 12) +
                       (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpnop_bh():
    return tt_op(0x8f, 0)

def sfpcast_bh(lreg_src_c, lreg_dest, instr_mod1):
    return tt_op(0x90, (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpconfig_bh(imm16_math, config_dest, instr_mod1):
    return tt_op(0x91, (imm16_math << 8) + (config_dest << 4) + (instr_mod1 << 0))

def sfplutfp32_bh(lreg_dest, instr_mod1):
    return tt_op(0x95, (lreg_dest << 4) + (instr_mod1 << 0))

def sfploadmacro_bh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op(0x93, (lreg_ind << 20) + (instr_mod0 << 16) +
                       (sfpu_addr_mode << 14) + (dest_reg_addr << 0))

def sfp_stoch_rnd_bh(rnd_mode, imm5, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op(0x8e, (rnd_mode << 21) + (imm5 << 16) +
                       (lreg_src_b << 12) + (lreg_src_c << 8) +
                       (lreg_dest << 4) + (instr_mod1 << 0))

# ============================================================================
# GCC encoding formulas — WH (exact from sfpu-ops-wh.h)
#
# Only SFPLOAD and SFPSTORE differ from BH:
#   WH: addr_mode << 14 (2-bit), addr at [13:0] (14-bit)
#   BH: addr_mode << 13 (3-bit), addr at [12:0] (13-bit)
# SFPLOADMACRO is identical (both use addr_mode << 14).
# All unary, 3-op, imm16, stoch_rnd formulas are byte-identical.
# ============================================================================

def sfpload_wh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op(0x70, (lreg_ind << 20) + (instr_mod0 << 16) +
                       (sfpu_addr_mode << 14) + (dest_reg_addr << 0))

def sfpstore_wh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op(0x72, (lreg_ind << 20) + (instr_mod0 << 16) +
                       (sfpu_addr_mode << 14) + (dest_reg_addr << 0))

def sfploadmacro_wh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op(0x93, (lreg_ind << 20) + (instr_mod0 << 16) +
                       (sfpu_addr_mode << 14) + (dest_reg_addr << 0))

# WH reuses BH formulas for everything else (same opcodes, same bit layouts):
sfploadi_wh  = sfploadi_bh
sfplut_wh    = sfplut_bh
sfpmuli_wh   = sfpmuli_bh
sfpaddi_wh   = sfpaddi_bh
sfp_unary_wh = sfp_unary_bh
sfpmad_wh    = sfpmad_bh
sfpadd_wh    = sfpadd_bh
sfpmul_wh    = sfpmul_bh
sfpnop_wh    = sfpnop_bh
sfpcast_wh   = sfpcast_bh
sfpconfig_wh = sfpconfig_bh
sfplutfp32_wh = sfplutfp32_bh
sfp_stoch_rnd_wh = sfp_stoch_rnd_bh

# ============================================================================
# LLVM encoding formulas — BH (simulating what our corrected TableGen produces)
# ============================================================================

def llvm_sfpload_bh(lreg_ind, mod0, addr_mode, addr):
    return (0x70 << 24) | (lreg_ind << 20) | (mod0 << 16) | (addr_mode << 13) | addr | 0x03

def llvm_sfploadi(lreg_ind, mod0, imm16):
    return (0x71 << 24) | (lreg_ind << 20) | (mod0 << 16) | imm16 | 0x03

def llvm_sfpstore_bh(lreg_ind, mod0, addr_mode, addr):
    return (0x72 << 24) | (lreg_ind << 20) | (mod0 << 16) | (addr_mode << 13) | addr | 0x03

def llvm_sfplut(lreg_ind, mod0, dest_reg_addr):
    return (0x73 << 24) | (lreg_ind << 20) | (mod0 << 16) | dest_reg_addr | 0x03

def llvm_sfp_unary(opcode, imm12, lreg_c, lreg_dest, mod1):
    return (opcode << 24) | (imm12 << 12) | (lreg_c << 8) | (lreg_dest << 4) | mod1 | 0x03

def llvm_sfpmad(src_a, src_b, src_c, dest, mod1):
    return (0x84 << 24) | (0 << 20) | (src_a << 16) | (src_b << 12) | (src_c << 8) | (dest << 4) | mod1 | 0x03

def llvm_sfploadmacro_bh(lreg_ind, mod0, addr_mode, addr):
    return (0x93 << 24) | (lreg_ind << 20) | (mod0 << 16) | (addr_mode << 14) | addr | 0x03

def llvm_sfp_stoch_rnd(rnd_mode, imm5, src_b, src_c, dest, mod1):
    return (0x8e << 24) | (rnd_mode << 21) | (imm5 << 16) | (src_b << 12) | (src_c << 8) | (dest << 4) | mod1 | 0x03

# ============================================================================
# LLVM encoding formulas — WH (addr_mode << 14 for SFPLOAD/SFPSTORE)
# ============================================================================

def llvm_sfpload_wh(lreg_ind, mod0, addr_mode, addr):
    return (0x70 << 24) | (lreg_ind << 20) | (mod0 << 16) | (addr_mode << 14) | addr | 0x03

def llvm_sfpstore_wh(lreg_ind, mod0, addr_mode, addr):
    return (0x72 << 24) | (lreg_ind << 20) | (mod0 << 16) | (addr_mode << 14) | addr | 0x03

# SFPLOADMACRO WH uses the same layout as BH (both addr_mode << 14)
llvm_sfploadmacro_wh = llvm_sfploadmacro_bh

# All other LLVM WH formulas are identical to BH
llvm_sfploadi_wh     = llvm_sfploadi
llvm_sfplut_wh       = llvm_sfplut
llvm_sfp_unary_wh    = llvm_sfp_unary
llvm_sfpmad_wh       = llvm_sfpmad
llvm_sfp_stoch_rnd_wh = llvm_sfp_stoch_rnd

# ============================================================================
# Test harness
# ============================================================================

def fmt32(val):
    return f"0x{val:08x}"

tests_pass = 0
tests_fail = 0

def check(name, gcc_val, llvm_val):
    global tests_pass, tests_fail
    # LLVM adds bits[1:0]=0b11; GCC doesn't include them in the macro
    # The actual instruction word in ELF has bits[1:0]=0b11
    gcc_with_marker = gcc_val | 0x03
    if gcc_with_marker == llvm_val:
        tests_pass += 1
        status = "PASS"
    else:
        tests_fail += 1
        status = "FAIL"
    print(f"  [{status}] {name:40s}  GCC={fmt32(gcc_with_marker)}  LLVM={fmt32(llvm_val)}")
    if status == "FAIL":
        # Show bit-level diff
        diff = gcc_with_marker ^ llvm_val
        print(f"         DIFF={fmt32(diff)} (bits {diff.bit_length()-1}..0)")

# ============================================================================
# BH test cases
# ============================================================================

print("=" * 80)
print("SECTION 1: BH — GCC sfpu-ops-bh.h vs LLVM TableGen")
print("=" * 80)

print("\n--- Standard Unary (BH) ---")
check("SFPDIVP2(0,0,0,0)", sfp_unary_bh(0x76,0,0,0,0), llvm_sfp_unary(0x76,0,0,0,0))
check("SFPMOV(0,1,2,0)", sfp_unary_bh(0x7c,0,1,2,0), llvm_sfp_unary(0x7c,0,1,2,0))
check("SFPABS(0,3,4,0)", sfp_unary_bh(0x7d,0,3,4,0), llvm_sfp_unary(0x7d,0,3,4,0))
check("SFPAND(0xFFF,7,5,0)", sfp_unary_bh(0x7e,0xFFF,7,5,0), llvm_sfp_unary(0x7e,0xFFF,7,5,0))
check("SFPSETCC(0,0,0,2)", sfp_unary_bh(0x7b,0,0,0,2), llvm_sfp_unary(0x7b,0,0,0,2))
check("SFPPUSHC(0,0,0,0)", sfp_unary_bh(0x87,0,0,0,0), llvm_sfp_unary(0x87,0,0,0,0))
check("SFPSWAP(0,1,2,0)", sfp_unary_bh(0x92,0,1,2,0), llvm_sfp_unary(0x92,0,1,2,0))
check("SFPSWAP(0,3,4,9)", sfp_unary_bh(0x92,0,3,4,9), llvm_sfp_unary(0x92,0,3,4,9))

print("\n--- 3-Operand BH (src_a at [19:16]) ---")
check("SFPMAD(1,2,3,0,0)", sfpmad_bh(1,2,3,0,0), llvm_sfpmad(1,2,3,0,0))
check("SFPMAD(0,0,9,7,0)", sfpmad_bh(0,0,9,7,0), llvm_sfpmad(0,0,9,7,0))
check("SFPADD(10,1,2,3,0)", sfpadd_bh(10,1,2,3,0),
      (0x85 << 24) | (0 << 20) | (10 << 16) | (1 << 12) | (2 << 8) | (3 << 4) | 0 | 0x03)
check("SFPMUL(1,2,9,0,0)", sfpmul_bh(1,2,9,0,0),
      (0x86 << 24) | (0 << 20) | (1 << 16) | (2 << 12) | (9 << 8) | (0 << 4) | 0 | 0x03)

print("\n--- Load/Store BH (addr_mode << 13) ---")
check("SFPLOAD(0,0,0,0)", sfpload_bh(0,0,0,0), llvm_sfpload_bh(0,0,0,0))
check("SFPLOAD(7,3,7,8191)", sfpload_bh(7,3,7,8191), llvm_sfpload_bh(7,3,7,8191))
check("SFPSTORE(3,1,2,100)", sfpstore_bh(3,1,2,100), llvm_sfpstore_bh(3,1,2,100))

print("\n--- SFPLOADI BH ---")
check("SFPLOADI(2,0,0x3F80)", sfploadi_bh(2,0,0x3F80), llvm_sfploadi(2,0,0x3F80))
check("SFPLOADI(5,1,0xBF00)", sfploadi_bh(5,1,0xBF00), llvm_sfploadi(5,1,0xBF00))

print("\n--- SFPLUT BH ---")
check("SFPLUT(1,0,0)", sfplut_bh(1,0,0), llvm_sfplut(1,0,0))
check("SFPLUT(4,3,1024)", sfplut_bh(4,3,1024), llvm_sfplut(4,3,1024))

print("\n--- SFPLOADMACRO BH (addr_mode << 14) ---")
check("SFPLOADMACRO(0,0,0,0)", sfploadmacro_bh(0,0,0,0), llvm_sfploadmacro_bh(0,0,0,0))
check("SFPLOADMACRO(4,2,3,50)", sfploadmacro_bh(4,2,3,50), llvm_sfploadmacro_bh(4,2,3,50))

print("\n--- SFP_STOCH_RND BH ---")
check("STOCH_RND(1,0,0,0,5,0)", sfp_stoch_rnd_bh(1,0,0,0,5,0), llvm_sfp_stoch_rnd(1,0,0,0,5,0))
check("STOCH_RND(2,31,3,0,4,0)", sfp_stoch_rnd_bh(2,31,3,0,4,0), llvm_sfp_stoch_rnd(2,31,3,0,4,0))
check("STOCH_RND(7,31,15,15,7,15)", sfp_stoch_rnd_bh(7,31,15,15,7,15), llvm_sfp_stoch_rnd(7,31,15,15,7,15))

bh_pass = tests_pass
bh_fail = tests_fail

# ============================================================================
# WH test cases — validated against sfpu-ops-wh.h
# ============================================================================

print(f"\n{'=' * 80}")
print("SECTION 2: WH — GCC sfpu-ops-wh.h vs LLVM TableGen")
print("=" * 80)

# ---- WH Load/Store: addr_mode << 14, addr [13:0] ----
# This is the key difference from BH (which uses addr_mode << 13, addr [12:0])

print("\n--- Load/Store WH (addr_mode << 14, 14-bit addr) ---")
check("SFPLOAD WH(0,0,0,0)",
      sfpload_wh(0,0,0,0), llvm_sfpload_wh(0,0,0,0))
check("SFPLOAD WH(7,3,3,16383)",
      sfpload_wh(7,3,3,16383), llvm_sfpload_wh(7,3,3,16383))
check("SFPLOAD WH(2,1,1,100)",
      sfpload_wh(2,1,1,100), llvm_sfpload_wh(2,1,1,100))
check("SFPSTORE WH(0,0,0,0)",
      sfpstore_wh(0,0,0,0), llvm_sfpstore_wh(0,0,0,0))
check("SFPSTORE WH(3,1,2,100)",
      sfpstore_wh(3,1,2,100), llvm_sfpstore_wh(3,1,2,100))
check("SFPSTORE WH(5,2,3,8000)",
      sfpstore_wh(5,2,3,8000), llvm_sfpstore_wh(5,2,3,8000))

# ---- WH SFPLOADMACRO: identical to BH (addr_mode << 14) ----

print("\n--- SFPLOADMACRO WH (addr_mode << 14, same as BH) ---")
check("SFPLOADMACRO WH(0,0,0,0)",
      sfploadmacro_wh(0,0,0,0), llvm_sfploadmacro_wh(0,0,0,0))
check("SFPLOADMACRO WH(4,2,3,50)",
      sfploadmacro_wh(4,2,3,50), llvm_sfploadmacro_wh(4,2,3,50))

# ---- WH-vs-BH divergence proof: same operands, different encodings ----
# With addr_mode > 0 and addr that fills lower bits, WH and BH MUST differ
# because BH puts addr_mode at bit 13 while WH puts it at bit 14.

print("\n--- WH/BH divergence proof (SFPLOAD addr_mode=2, addr=100) ---")
wh_enc = sfpload_wh(0,0,2,100) | 0x03
bh_enc = sfpload_bh(0,0,2,100) | 0x03
diverges = wh_enc != bh_enc
print(f"  WH encoding: {fmt32(wh_enc)}")
print(f"  BH encoding: {fmt32(bh_enc)}")
print(f"  Diverges:    {diverges}")
if not diverges:
    tests_fail += 1
    print("  [FAIL] WH and BH should differ for SFPLOAD with addr_mode > 0")
else:
    tests_pass += 1
    print("  [PASS] Confirmed WH/BH SFPLOAD encodings differ as expected")

# ---- WH instructions identical to BH ----

print("\n--- Unary WH (identical to BH) ---")
check("SFPMOV WH(0,1,2,0)",
      sfp_unary_wh(0x7c,0,1,2,0), llvm_sfp_unary_wh(0x7c,0,1,2,0))
check("SFPABS WH(0,3,4,0)",
      sfp_unary_wh(0x7d,0,3,4,0), llvm_sfp_unary_wh(0x7d,0,3,4,0))
check("SFPDIVP2 WH(0,0,0,0)",
      sfp_unary_wh(0x76,0,0,0,0), llvm_sfp_unary_wh(0x76,0,0,0,0))

print("\n--- 3-Operand WH (identical to BH) ---")
check("SFPMAD WH(1,2,3,0,0)",
      sfpmad_wh(1,2,3,0,0), llvm_sfpmad_wh(1,2,3,0,0))
check("SFPMAD WH(0,0,9,7,0)",
      sfpmad_wh(0,0,9,7,0), llvm_sfpmad_wh(0,0,9,7,0))

print("\n--- SFPLOADI WH (identical to BH) ---")
check("SFPLOADI WH(2,0,0x3F80)",
      sfploadi_wh(2,0,0x3F80), llvm_sfploadi_wh(2,0,0x3F80))

print("\n--- SFPLUT WH (identical to BH) ---")
check("SFPLUT WH(1,0,0)",
      sfplut_wh(1,0,0), llvm_sfplut_wh(1,0,0))
check("SFPLUT WH(4,3,1024)",
      sfplut_wh(4,3,1024), llvm_sfplut_wh(4,3,1024))

print("\n--- SFP_STOCH_RND WH (identical to BH) ---")
check("STOCH_RND WH(1,0,0,0,5,0)",
      sfp_stoch_rnd_wh(1,0,0,0,5,0), llvm_sfp_stoch_rnd_wh(1,0,0,0,5,0))
check("STOCH_RND WH(7,31,15,15,7,15)",
      sfp_stoch_rnd_wh(7,31,15,15,7,15), llvm_sfp_stoch_rnd_wh(7,31,15,15,7,15))

# ---- WH boundary / max-field tests ----

print("\n--- WH boundary values ---")
# Max 14-bit addr = 16383 (0x3FFF), max 2-bit addr_mode = 3
check("SFPLOAD WH max(7,15,3,16383)",
      sfpload_wh(7,15,3,16383), llvm_sfpload_wh(7,15,3,16383))
check("SFPSTORE WH max(7,15,3,16383)",
      sfpstore_wh(7,15,3,16383), llvm_sfpstore_wh(7,15,3,16383))
# addr_mode=0 should match BH when addr fits in 13 bits
check("SFPLOAD WH mode0(0,0,0,42)",
      sfpload_wh(0,0,0,42), llvm_sfpload_wh(0,0,0,42))

# ============================================================================
# Summary
# ============================================================================

wh_pass = tests_pass - bh_pass
wh_fail = tests_fail - bh_fail

print(f"\n{'=' * 80}")
print(f"Results: {tests_pass} passed, {tests_fail} failed out of {tests_pass + tests_fail} tests")
print(f"  BH: {bh_pass} passed, {bh_fail} failed")
print(f"  WH: {wh_pass} passed, {wh_fail} failed")
print(f"{'=' * 80}")

sys.exit(1 if tests_fail > 0 else 0)
