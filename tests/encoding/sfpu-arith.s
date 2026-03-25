# RUN: %llvm-mc %sfpu-bh-flags -filetype=obj %s | \
# RUN:   %llvm-mc %sfpu-bh-flags -filetype=asm -disassemble | \
# RUN:   %FileCheck %s
#
# Test SFPU arithmetic instruction encoding:
# - 3-operand: SFPMAD, SFPADD, SFPMUL (2-cycle, MAD unit)
# - Immediate-16: SFPMULI, SFPADDI (2-cycle, MAD unit)
# - SFPMUL24 (BH-only, C-026)
#
# Reference: ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.5
#            ttsim-analysis/ERRATA.md C-010, C-026

# --- SFPMAD (opcode 0x84) ---
# dest = src_a * src_b + src_c

# CHECK: sfpmad l0, l1, l2, l3, 0
sfpmad l0, l1, l2, l3, 0     # Basic MAD

# CHECK: sfpmad l7, l0, l8, l9, 0
sfpmad l7, l0, l8, l9, 0     # Using constants: L8=0.8373, L9=0.0

# CHECK: sfpmad l5, l3, l10, l11, 0
sfpmad l5, l3, l10, l11, 0   # L10=1.0, L11=-1.0

# --- SFPADD (opcode 0x85) ---

# CHECK: sfpadd l0, l1, l2, l3, 0
sfpadd l0, l1, l2, l3, 0

# CHECK: sfpadd l4, l10, l5, l6, 0
sfpadd l4, l10, l5, l6, 0    # WH pattern: src_a = L10 (1.0)

# --- SFPMUL (opcode 0x86) ---

# CHECK: sfpmul l0, l1, l2, l9, 0
sfpmul l0, l1, l2, l9, 0     # Typical: src_c = L9 (zero)

# CHECK: sfpmul l3, l4, l5, l9, 0
sfpmul l3, l4, l5, l9, 0

# --- SFPMULI (opcode 0x74, Imm16 format) ---

# CHECK: sfpmuli l0, 16256, 0
sfpmuli l0, 16256, 0         # Multiply by 1.0 in bf16

# CHECK: sfpmuli l3, 0, 0
sfpmuli l3, 0, 0             # Multiply by 0

# --- SFPADDI (opcode 0x75, Imm16 format) ---

# CHECK: sfpaddi l1, 16256, 0
sfpaddi l1, 16256, 0         # Add 1.0 in bf16

# CHECK: sfpaddi l5, 48896, 0
sfpaddi l5, 48896, 0         # Add -0.5

# --- SFPMUL24 (BH-only, opcode 0x96) ---
# 23b x 23b integer multiply, src_c must be L9 (C-026)

# CHECK: sfpmul24 l0, l1, l2, l9, 0
sfpmul24 l0, l1, l2, l9, 0   # Standard usage with L9 as src_c
