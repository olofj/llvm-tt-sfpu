#!/usr/bin/env python3
"""
validate_encoding.py — Cross-validate LLVM XttSFPU encoding against GCC sfpu-ops-bh.h

Computes expected 32-bit instruction words using the exact GCC macro formulas.
All formulas verified against sfpi-gcc/gcc/config/riscv/tt/sfpu-ops-bh.h.
"""

import sys

def tt_op_bh(opcode, params):
    return (opcode << 24) + params

# ============================================================================
# GCC encoding formulas (exact from sfpu-ops-bh.h)
# ============================================================================

def sfpload_bh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op_bh(0x70, (lreg_ind << 20) + (instr_mod0 << 16) +
                          (sfpu_addr_mode << 13) + (dest_reg_addr << 0))

def sfploadi_bh(lreg_ind, instr_mod0, imm16):
    return tt_op_bh(0x71, (lreg_ind << 20) + (instr_mod0 << 16) + (imm16 << 0))

def sfpstore_bh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op_bh(0x72, (lreg_ind << 20) + (instr_mod0 << 16) +
                          (sfpu_addr_mode << 13) + (dest_reg_addr << 0))

def sfplut_bh(lreg_ind, instr_mod0, dest_reg_addr):
    return tt_op_bh(0x73, (lreg_ind << 20) + (instr_mod0 << 16) + (dest_reg_addr << 0))

def sfpmuli_bh(imm16_math, lreg_dest, instr_mod1):
    return tt_op_bh(0x74, (imm16_math << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpaddi_bh(imm16_math, lreg_dest, instr_mod1):
    return tt_op_bh(0x75, (imm16_math << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfp_unary_bh(opcode, imm12_math, lreg_c, lreg_dest, instr_mod1):
    return tt_op_bh(opcode, (imm12_math << 12) + (lreg_c << 8) +
                            (lreg_dest << 4) + (instr_mod1 << 0))

def sfpmad_bh(lreg_src_a, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op_bh(0x84, (lreg_src_a << 16) + (lreg_src_b << 12) +
                          (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpadd_bh(lreg_src_a, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op_bh(0x85, (lreg_src_a << 16) + (lreg_src_b << 12) +
                          (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpmul_bh(lreg_src_a, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op_bh(0x86, (lreg_src_a << 16) + (lreg_src_b << 12) +
                          (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpnop_bh():
    return tt_op_bh(0x8f, 0)

def sfpcast_bh(lreg_src_c, lreg_dest, instr_mod1):
    return tt_op_bh(0x90, (lreg_src_c << 8) + (lreg_dest << 4) + (instr_mod1 << 0))

def sfpconfig_bh(imm16_math, config_dest, instr_mod1):
    return tt_op_bh(0x91, (imm16_math << 8) + (config_dest << 4) + (instr_mod1 << 0))

def sfplutfp32_bh(lreg_dest, instr_mod1):
    return tt_op_bh(0x95, (lreg_dest << 4) + (instr_mod1 << 0))

def sfploadmacro_bh(lreg_ind, instr_mod0, sfpu_addr_mode, dest_reg_addr):
    return tt_op_bh(0x93, (lreg_ind << 20) + (instr_mod0 << 16) +
                          (sfpu_addr_mode << 14) + (dest_reg_addr << 0))

def sfp_stoch_rnd_bh(rnd_mode, imm5, lreg_src_b, lreg_src_c, lreg_dest, instr_mod1):
    return tt_op_bh(0x8e, (rnd_mode << 21) + (imm5 << 16) +
                          (lreg_src_b << 12) + (lreg_src_c << 8) +
                          (lreg_dest << 4) + (instr_mod1 << 0))

# ============================================================================
# LLVM encoding formulas (simulating what our corrected TableGen produces)
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
# Test cases — compare GCC (no bits[1:0]) with LLVM (with bits[1:0]=0b11)
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

print("=" * 80)
print("SFPU Encoding Cross-Validation: GCC sfpu-ops-bh.h vs LLVM TableGen")
print("=" * 80)

print("\n--- Standard Unary ---")
check("SFPDIVP2(0,0,0,0)", sfp_unary_bh(0x76,0,0,0,0), llvm_sfp_unary(0x76,0,0,0,0))
check("SFPMOV(0,1,2,0)", sfp_unary_bh(0x7c,0,1,2,0), llvm_sfp_unary(0x7c,0,1,2,0))
check("SFPABS(0,3,4,0)", sfp_unary_bh(0x7d,0,3,4,0), llvm_sfp_unary(0x7d,0,3,4,0))
check("SFPAND(0xFFF,7,5,0)", sfp_unary_bh(0x7e,0xFFF,7,5,0), llvm_sfp_unary(0x7e,0xFFF,7,5,0))
check("SFPSETCC(0,0,0,2)", sfp_unary_bh(0x7b,0,0,0,2), llvm_sfp_unary(0x7b,0,0,0,2))
check("SFPPUSHC(0,0,0,0)", sfp_unary_bh(0x87,0,0,0,0), llvm_sfp_unary(0x87,0,0,0,0))
check("SFPSWAP(0,1,2,0)", sfp_unary_bh(0x92,0,1,2,0), llvm_sfp_unary(0x92,0,1,2,0))
check("SFPSWAP(0,3,4,9)", sfp_unary_bh(0x92,0,3,4,9), llvm_sfp_unary(0x92,0,3,4,9))

print("\n--- 3-Operand (CORRECTED: src_a at [19:16]) ---")
check("SFPMAD(1,2,3,0,0)", sfpmad_bh(1,2,3,0,0), llvm_sfpmad(1,2,3,0,0))
check("SFPMAD(0,0,9,7,0)", sfpmad_bh(0,0,9,7,0), llvm_sfpmad(0,0,9,7,0))
check("SFPADD(10,1,2,3,0)", sfpadd_bh(10,1,2,3,0),
      (0x85 << 24) | (0 << 20) | (10 << 16) | (1 << 12) | (2 << 8) | (3 << 4) | 0 | 0x03)
check("SFPMUL(1,2,9,0,0)", sfpmul_bh(1,2,9,0,0),
      (0x86 << 24) | (0 << 20) | (1 << 16) | (2 << 12) | (9 << 8) | (0 << 4) | 0 | 0x03)

print("\n--- Load/Store BH ---")
check("SFPLOAD(0,0,0,0)", sfpload_bh(0,0,0,0), llvm_sfpload_bh(0,0,0,0))
check("SFPLOAD(7,3,7,8191)", sfpload_bh(7,3,7,8191), llvm_sfpload_bh(7,3,7,8191))
check("SFPSTORE(3,1,2,100)", sfpstore_bh(3,1,2,100), llvm_sfpstore_bh(3,1,2,100))

print("\n--- SFPLOADI (CORRECTED: Load format) ---")
check("SFPLOADI(2,0,0x3F80)", sfploadi_bh(2,0,0x3F80), llvm_sfploadi(2,0,0x3F80))
check("SFPLOADI(5,1,0xBF00)", sfploadi_bh(5,1,0xBF00), llvm_sfploadi(5,1,0xBF00))

print("\n--- SFPLUT (CORRECTED: no addr_mode) ---")
check("SFPLUT(1,0,0)", sfplut_bh(1,0,0), llvm_sfplut(1,0,0))
check("SFPLUT(4,3,1024)", sfplut_bh(4,3,1024), llvm_sfplut(4,3,1024))

print("\n--- SFPLOADMACRO BH (CORRECTED: 2-bit addr_mode) ---")
check("SFPLOADMACRO(0,0,0,0)", sfploadmacro_bh(0,0,0,0), llvm_sfploadmacro_bh(0,0,0,0))
check("SFPLOADMACRO(4,2,3,50)", sfploadmacro_bh(4,2,3,50), llvm_sfploadmacro_bh(4,2,3,50))

print("\n--- SFP_STOCH_RND (CORRECTED: 3-bit rnd, 5-bit imm, 6 operands) ---")
check("STOCH_RND(1,0,0,0,5,0)", sfp_stoch_rnd_bh(1,0,0,0,5,0), llvm_sfp_stoch_rnd(1,0,0,0,5,0))
check("STOCH_RND(2,31,3,0,4,0)", sfp_stoch_rnd_bh(2,31,3,0,4,0), llvm_sfp_stoch_rnd(2,31,3,0,4,0))
check("STOCH_RND(7,31,15,15,7,15)", sfp_stoch_rnd_bh(7,31,15,15,7,15), llvm_sfp_stoch_rnd(7,31,15,15,7,15))

print(f"\n{'=' * 80}")
print(f"Results: {tests_pass} passed, {tests_fail} failed out of {tests_pass + tests_fail} tests")
print(f"{'=' * 80}")

sys.exit(1 if tests_fail > 0 else 0)
