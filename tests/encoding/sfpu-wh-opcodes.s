# WH-compatible opcode subset
# RUN: %llvm-mc %sfpu-bh-flags -filetype=obj %s | \
# RUN:   %llvm-mc %sfpu-bh-flags -filetype=asm -disassemble | \
# RUN:   %FileCheck %s
#
# Round-trip encoding test for all SFPU instructions.
# All encodings validated against sfpu-ops-bh.h (GCC golden reference).
#
# Encoding formulas from sfpi-gcc:
#   Unary:  (opcode << 24) | (imm12 << 12) | (lreg_c << 8) | (dest << 4) | mod1
#   3-Op:   (opcode << 24) | (src_a << 16) | (src_b << 12) | (src_c << 8) | (dest << 4) | mod1
#   LoadBH: (opcode << 24) | (lreg << 20) | (mod0 << 16) | (addr_mode << 13) | addr
#   LoadI:  (opcode << 24) | (lreg << 20) | (mod0 << 16) | imm16
#   Imm16:  (opcode << 24) | (imm16 << 8) | (dest << 4) | mod1
#   LUT:    (opcode << 24) | (lreg << 20) | (mod0 << 16) | dest_reg_addr
#   StochRnd: (opcode << 24) | (rnd << 21) | (imm5 << 16) | (src_b << 12) | (src_c << 8) | (dest << 4) | mod1

# --- Load/Store (BH encoding: 3-bit addr_mode, 13-bit addr) ---

# CHECK: sfpload l0, 0, 0, 0
sfpload l0, 0, 0, 0

# CHECK: sfpload l7, 3, 3, 8191
sfpload l7, 3, 3, 8191

# SFPLOADI uses Load format: lreg + mod0 + imm16
# CHECK: sfploadi l2, 0, 16256
sfploadi l2, 0, 16256              # 16256 = 0x3F80 (1.0 in bf16)

# CHECK: sfploadi l5, 1, 48896
sfploadi l5, 1, 48896              # 48896 = 0xBF00 (-0.5 in fp16)

# CHECK: sfpstore l3, 1, 2, 100
sfpstore l3, 1, 2, 100

# SFPLUT: no addr_mode field, dest_reg_addr at [15:0]
# CHECK: sfplut l1, 0, 0
sfplut l1, 0, 0

# CHECK: sfplut l4, 3, 1024
sfplut l4, 3, 1024

# SFPLOADMACRO BH: 2-bit addr_mode (C-012), NOT 3-bit like SFPLOAD
# CHECK: sfploadmacro l4, 2, 1, 50
sfploadmacro l4, 2, 1, 50

# --- Immediate-16 Arithmetic ---

# CHECK: sfpmuli l0, 16256, 0
sfpmuli l0, 16256, 0

# CHECK: sfpaddi l1, 16256, 0
sfpaddi l1, 16256, 0

# --- Standard Unary ---

# CHECK: sfpdivp2 l0, l1, 0, 0
sfpdivp2 l0, l1, 0, 0

# CHECK: sfpexexp l2, l3, 0, 0
sfpexexp l2, l3, 0, 0

# CHECK: sfpexman l0, l2, 0, 0
sfpexman l0, l2, 0, 0

# CHECK: sfpiadd l1, l3, 100, 0
sfpiadd l1, l3, 100, 0

# CHECK: sfpshft l2, l4, 5, 0
sfpshft l2, l4, 5, 0

# CHECK: sfpsetcc 0, l1, 0, 0
sfpsetcc 0, l1, 0, 0

# CHECK: sfpmov l3, l5, 0, 0
sfpmov l3, l5, 0, 0

# CHECK: sfpabs l4, l6, 0, 0
sfpabs l4, l6, 0, 0

# CHECK: sfpand l5, l7, 0, 0
sfpand l5, l7, 0, 0

# CHECK: sfpor l6, l0, 0, 0
sfpor l6, l0, 0, 0

# CHECK: sfpnot l7, l1, 0, 0
sfpnot l7, l1, 0, 0

# CHECK: sfplz l0, l2, 0, 0
sfplz l0, l2, 0, 0

# CHECK: sfpsetexp l1, l3, 0, 0
sfpsetexp l1, l3, 0, 0

# CHECK: sfpsetman l2, l4, 0, 0
sfpsetman l2, l4, 0, 0

# --- 3-Operand (CORRECTED: bits[23:20] empty, src_a at [19:16]) ---

# CHECK: sfpmad l0, l1, l2, l3, 0
sfpmad l0, l1, l2, l3, 0

# CHECK: sfpadd l4, l5, l6, l7, 0
sfpadd l4, l5, l6, l7, 0

# CHECK: sfpmul l0, l1, l2, l9, 0
sfpmul l0, l1, l2, l9, 0

# --- CC Stack ---

# CHECK: sfppushc 0, l0, 0, 0
sfppushc 0, l0, 0, 0

# CHECK: sfppopc 0, l0, 0, 0
sfppopc 0, l0, 0, 0

# CHECK: sfpsetsgn l3, l4, 0, 0
sfpsetsgn l3, l4, 0, 0

# CHECK: sfpencc 0, l0, 0, 0
sfpencc 0, l0, 0, 0

# CHECK: sfpcompc 0, l0, 0, 0
sfpcompc 0, l0, 0, 0

# --- Cross-Lane ---

# CHECK: sfptransp l1, l2, 0, 0
sfptransp l1, l2, 0, 0

# CHECK: sfpxor l3, l4, 0, 0
sfpxor l3, l4, 0, 0

# --- Stochastic Rounding (CORRECTED: 3-bit rnd, 5-bit imm, 6 operands) ---

# CHECK: sfpstochrnd l5, 1, 0, l0, l0, 0
sfpstochrnd l5, 1, 0, l0, l0, 0

# --- NOP ---

# CHECK: sfpnop
sfpnop

# --- SFPCAST ---

# CHECK: sfpcast l0, l1, 0, 0
sfpcast l0, l1, 0, 0

# --- SFPCONFIG ---

# CHECK: sfpconfig 11, 1024, 0
sfpconfig 11, 1024, 0

# --- SFPSWAP ---

# CHECK: sfpswap l0, l1, 0, 0
sfpswap l0, l1, 0, 0

# CHECK: sfpswap l4, l5, 0, 9
sfpswap l4, l5, 0, 9

# --- SFPSHFT2 ---

# CHECK: sfpshft2 l0, l1, 0, 0
sfpshft2 l0, l1, 0, 0

# --- SFPLUTFP32 ---

# CHECK: sfplutfp32 l0, l2, 0
sfplutfp32 l0, l2, 0

# --- BH-Only ---




