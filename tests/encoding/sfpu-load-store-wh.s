# RUN: %llvm-mc %sfpu-wh-flags -filetype=obj %s | \
# RUN:   %llvm-mc %sfpu-wh-flags -filetype=asm -disassemble | \
# RUN:   %FileCheck %s
#
# Test WH-specific SFPLOAD/SFPSTORE encoding:
# - WH: 2-bit addr_mode [15:14], 14-bit addr [13:0]
# - Verify field widths match WH encoding (not BH's 3-bit/13-bit)
#
# Encoding formula (WH):
#   LoadWH: (opcode << 24) | (lreg << 20) | (mod0 << 16) | (addr_mode << 14) | addr
#
# Reference: ttsim-analysis/ISA_SPEC.md Section 3.4
#            ttsim-analysis/ERRATA.md C-003, C-004, C-013, E-005

# --- SFPLOAD WH encoding ---

# CHECK: sfpload l0, 0, 0, 0
sfpload l0, 0, 0, 0              # Min values

# CHECK: sfpload l7, 15, 3, 16383
sfpload l7, 15, 3, 16383         # Max values (mod0=0xF, addr_mode=0x3, addr=0x3FFF)

# CHECK: sfpload l3, 2, 1, 256
sfpload l3, 2, 1, 256            # Typical: mod0=FP32, addr_mode=1, addr=256

# CHECK: sfpload l0, 0, 2, 8192
sfpload l0, 0, 2, 8192           # addr=8192 (exceeds BH's 13-bit but fits WH's 14-bit)

# CHECK: sfpload l5, 0, 3, 10000
sfpload l5, 0, 3, 10000          # addr=10000 (within WH 14-bit range)

# --- SFPSTORE WH encoding ---
# Valid store sources: L0-L11, L16 (E-005: L12-L15 prohibited)

# CHECK: sfpstore l0, 0, 0, 0
sfpstore l0, 0, 0, 0             # L0 as source (valid)

# CHECK: sfpstore l7, 1, 2, 100
sfpstore l7, 1, 2, 100           # L7 with addr_mode=2

# CHECK: sfpstore l11, 0, 0, 50
sfpstore l11, 0, 0, 50           # L11 as source (boundary)

# CHECK: sfpstore l0, 0, 3, 16383
sfpstore l0, 0, 3, 16383         # Max addr_mode and addr for WH

# --- SFPLUT (arch-independent: LUT format with lreg, mod0, dest_reg_addr) ---

# CHECK: sfplut l0, 0, 0
sfplut l0, 0, 0

# CHECK: sfplut l4, 3, 1024
sfplut l4, 3, 1024

# --- SFPLOADMACRO WH ---
# CHECK: sfploadmacro l0, 0, 0, 0
sfploadmacro l0, 0, 0, 0

# CHECK: sfploadmacro l4, 2, 1, 50
sfploadmacro l4, 2, 1, 50

# --- SFPLOADI (format shared between WH and BH) ---

# CHECK: sfploadi l0, 0, 0
sfploadi l0, 0, 0                 # FLOATB mode, imm=0

# CHECK: sfploadi l3, 0, 16256
sfploadi l3, 0, 16256             # 0x3F80 (1.0 in bf16)

# CHECK: sfploadi l2, 0, 65535
sfploadi l2, 0, 65535             # Max imm16

# --- Unary instructions (shared encoding, verify on WH target) ---

# CHECK: sfpmov l3, l5, 0, 0
sfpmov l3, l5, 0, 0

# CHECK: sfpmad l0, l1, l2, l3, 0
sfpmad l0, l1, l2, l3, 0

# CHECK: sfpmul l4, l5, l9, l6, 0
sfpmul l4, l5, l9, l6, 0

# CHECK: sfpadd l0, l10, l1, l2, 0
sfpadd l0, l10, l1, l2, 0

# CHECK: sfpnop
sfpnop
