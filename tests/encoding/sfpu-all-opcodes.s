# RUN: %llvm-mc %sfpu-bh-flags -filetype=obj %s | \
# RUN:   %llvm-mc %sfpu-bh-flags -filetype=asm -disassemble | \
# RUN:   %FileCheck %s
#
# Test round-trip encoding/decoding for all 38 base SFPU instructions
# plus BH-only extensions. Verifies correct opcode encoding and operand
# field placement.
#
# Reference: ttsim-analysis/ERRATA.md C-006 (complete opcode map)
#            ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.4-3.5

# --- Load/Store (BH encoding: 3-bit addr_mode, 13-bit addr) ---

# CHECK: sfpload l0, 0, 0, 0
sfpload l0, 0, 0, 0          # opcode=0x70, lreg=0, mod0=0, addr_mode=0, addr=0

# CHECK: sfpload l7, 3, 7, 8191
sfpload l7, 3, 7, 8191       # opcode=0x70, lreg=7, mod0=3, addr_mode=7, addr=max

# CHECK: sfploadi l2, 65535, 0
sfploadi l2, 65535, 0         # opcode=0x71, imm16=max, mod1=0

# CHECK: sfploadi l5, 0, 10
sfploadi l5, 0, 10            # opcode=0x71, imm16=0, mod1=LOWER

# CHECK: sfpstore l3, 1, 2, 100
sfpstore l3, 1, 2, 100       # opcode=0x72, lreg=3, mod0=1, addr_mode=2, addr=100

# CHECK: sfplut l1, 0, 0, 0
sfplut l1, 0, 0, 0           # opcode=0x73

# CHECK: sfploadmacro l4, 2, 1, 50
sfploadmacro l4, 2, 1, 50    # opcode=0x93

# --- Immediate-16 Arithmetic ---

# CHECK: sfpmuli l0, 1000, 0
sfpmuli l0, 1000, 0          # opcode=0x74, 2-cycle

# CHECK: sfpaddi l1, 500, 0
sfpaddi l1, 500, 0           # opcode=0x75, 2-cycle

# --- Standard Unary (simple unit, 1 cycle) ---

# CHECK: sfpdivp2 l0, l1, 0, 0
sfpdivp2 l0, l1, 0, 0        # opcode=0x76

# CHECK: sfpexexp l2, l3, 0, 0
sfpexexp l2, l3, 0, 0        # opcode=0x77

# CHECK: sfpexexp l4, l5, 0, 1
sfpexexp l4, l5, 0, 1        # opcode=0x77, mod1=NODEBIAS

# CHECK: sfpexman l0, l2, 0, 0
sfpexman l0, l2, 0, 0        # opcode=0x78

# CHECK: sfpiadd l1, l3, 100, 0
sfpiadd l1, l3, 100, 0       # opcode=0x79

# CHECK: sfpshft l2, l4, 5, 0
sfpshft l2, l4, 5, 0         # opcode=0x7A

# CHECK: sfpsetcc l0, l1, 0, 0
sfpsetcc l0, l1, 0, 0        # opcode=0x7B, mod1=LREG_LT0

# CHECK: sfpsetcc l2, l3, 0, 2
sfpsetcc l2, l3, 0, 2        # opcode=0x7B, mod1=LREG_NE0

# CHECK: sfpmov l3, l5, 0, 0
sfpmov l3, l5, 0, 0          # opcode=0x7C

# CHECK: sfpabs l4, l6, 0, 0
sfpabs l4, l6, 0, 0          # opcode=0x7D

# CHECK: sfpand l5, l7, 0, 0
sfpand l5, l7, 0, 0          # opcode=0x7E

# CHECK: sfpor l6, l0, 0, 0
sfpor l6, l0, 0, 0           # opcode=0x7F

# CHECK: sfpnot l7, l1, 0, 0
sfpnot l7, l1, 0, 0          # opcode=0x80

# CHECK: sfplz l0, l2, 0, 0
sfplz l0, l2, 0, 0           # opcode=0x81

# CHECK: sfpsetexp l1, l3, 0, 0
sfpsetexp l1, l3, 0, 0       # opcode=0x82

# CHECK: sfpsetman l2, l4, 0, 0
sfpsetman l2, l4, 0, 0       # opcode=0x83

# --- 3-Operand Arithmetic (MAD unit, 2 cycles) ---

# CHECK: sfpmad l0, l1, l2, l3, 0
sfpmad l0, l1, l2, l3, 0     # opcode=0x84, dest = l1*l2 + l3

# CHECK: sfpadd l4, l5, l6, l7, 0
sfpadd l4, l5, l6, l7, 0     # opcode=0x85

# CHECK: sfpmul l0, l1, l2, l9, 0
sfpmul l0, l1, l2, l9, 0     # opcode=0x86, src_c=L9 (zero, typical for mul)

# --- CC Stack / Predication ---

# CHECK: sfppushc l0, l0, 0, 0
sfppushc l0, l0, 0, 0        # opcode=0x87

# CHECK: sfppopc l0, l0, 0, 0
sfppopc l0, l0, 0, 0         # opcode=0x88

# CHECK: sfpsetsgn l3, l4, 0, 0
sfpsetsgn l3, l4, 0, 0       # opcode=0x89

# CHECK: sfpencc l0, l0, 0, 0
sfpencc l0, l0, 0, 0         # opcode=0x8A

# CHECK: sfpcompc l0, l0, 0, 0
sfpcompc l0, l0, 0, 0        # opcode=0x8B

# --- Cross-Lane / Transpose ---

# CHECK: sfptransp l1, l2, 0, 0
sfptransp l1, l2, 0, 0       # opcode=0x8C

# CHECK: sfpxor l3, l4, 0, 0
sfpxor l3, l4, 0, 0          # opcode=0x8D

# --- Stochastic Rounding ---

# CHECK: sfpstochrnd l5, 1, 0, l0, 0
sfpstochrnd l5, 1, 0, l0, 0  # opcode=0x8E, rnd_mode=1(FP32_TO_FP16B)

# --- NOP ---

# CHECK: sfpnop
sfpnop                        # opcode=0x8F

# --- SFPCAST ---

# CHECK: sfpcast l0, l1, 0, 0
sfpcast l0, l1, 0, 0         # opcode=0x90, mod1=FP32_TO_FP16A

# CHECK: sfpcast l2, l3, 0, 3
sfpcast l2, l3, 0, 3         # opcode=0x90, mod1=FP16B_TO_FP32

# --- SFPCONFIG ---

# CHECK: sfpconfig 11, 1024, 0
sfpconfig 11, 1024, 0        # opcode=0x91, VD=11 (write to L11)

# --- SFPSWAP (2 cycle) ---

# CHECK: sfpswap l0, l1, 0, 0
sfpswap l0, l1, 0, 0         # opcode=0x92, mod1=SWAP

# CHECK: sfpswap l2, l3, 0, 1
sfpswap l2, l3, 0, 1         # opcode=0x92, mod1=MIN

# CHECK: sfpswap l4, l5, 0, 9
sfpswap l4, l5, 0, 9         # opcode=0x92, mod1=MAX (C-025)

# --- SFPSHFT2 ---

# CHECK: sfpshft2 l0, l1, 0, 0
sfpshft2 l0, l1, 0, 0        # opcode=0x94

# --- SFPLUTFP32 (2 cycle, writes L0, L1, L7) ---

# CHECK: sfplutfp32 l0, l2, 0
sfplutfp32 l0, l2, 0         # opcode=0x95

# --- BH-Only Instructions (C-009) ---

# CHECK: sfpmul24 l0, l1, l2, l9, 0
sfpmul24 l0, l1, l2, l9, 0   # opcode=0x96, src_c must be L9

# CHECK: sfparecip l3, l4, 0, 0
sfparecip l3, l4, 0, 0       # opcode=0x99

# CHECK: sfpgt l0, l1, 0, 0
sfpgt l0, l1, 0, 0           # opcode=0x9A

# CHECK: sfple l2, l3, 0, 0
sfple l2, l3, 0, 0           # opcode=0x9B
