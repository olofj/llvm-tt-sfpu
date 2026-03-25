# RUN: %llvm-mc %sfpu-bh-flags -filetype=obj %s | \
# RUN:   %llvm-mc %sfpu-bh-flags -filetype=asm -disassemble | \
# RUN:   %FileCheck %s
#
# Test SFPLOAD/SFPSTORE encoding variants:
# - BH: 3-bit addr_mode [15:13], 13-bit addr [12:0]
# - Verify E-005: L12-L15 cannot be SFPSTORE source
#
# Reference: ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.5
#            ttsim-analysis/ERRATA.md C-003, C-004, C-013, E-005

# --- SFPLOAD BH encoding ---

# CHECK: sfpload l0, 0, 0, 0
sfpload l0, 0, 0, 0          # Min values

# CHECK: sfpload l7, 15, 7, 8191
sfpload l7, 15, 7, 8191      # Max values (mod0=0xF, addr_mode=0x7, addr=0x1FFF)

# CHECK: sfpload l3, 2, 4, 256
sfpload l3, 2, 4, 256        # Typical: mod0=FP32, addr_mode=4, addr=256

# --- SFPSTORE BH encoding ---
# Valid store sources: L0-L11, L16

# CHECK: sfpstore l0, 0, 0, 0
sfpstore l0, 0, 0, 0         # L0 as source (valid)

# CHECK: sfpstore l7, 1, 2, 100
sfpstore l7, 1, 2, 100       # L7 as source (valid)

# CHECK: sfpstore l11, 0, 0, 50
sfpstore l11, 0, 0, 50       # L11 as source (valid, boundary)

# NOTE: sfpstore l12/l13/l14/l15 should produce an error (E-005)
# These are tested in error tests, not here.

# --- SFPLOADI (Imm16 format) ---

# CHECK: sfploadi l0, 0, 0
sfploadi l0, 0, 0             # FLOATB mode, imm=0

# CHECK: sfploadi l3, 16256, 0
sfploadi l3, 16256, 0         # FLOATB mode, imm=0x3F80 (1.0 in bf16)

# CHECK: sfploadi l5, 48896, 1
sfploadi l5, 48896, 1         # FLOATA mode, imm=0xBF00 (-0.5 in fp16)

# CHECK: sfploadi l1, 255, 2
sfploadi l1, 255, 2           # USHORT mode

# CHECK: sfploadi l2, 65535, 4
sfploadi l2, 65535, 4         # SHORT mode, imm=max signed

# --- SFPLUT ---

# CHECK: sfplut l0, 0, 0, 0
sfplut l0, 0, 0, 0

# CHECK: sfplut l4, 3, 2, 1024
sfplut l4, 3, 2, 1024

# --- SFPLOADMACRO ---
# Note: E-013 says SFPLOADMACRO is only valid inside REPLAY/MOP context

# CHECK: sfploadmacro l0, 0, 0, 0
sfploadmacro l0, 0, 0, 0
