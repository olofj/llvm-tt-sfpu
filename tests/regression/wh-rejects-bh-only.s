# RUN: not %llvm-mc %sfpu-wh-flags %s 2>&1 | %FileCheck %s
#
# Verify that BH-only instructions are rejected when targeting Wormhole.
# WH does not have: SFPMUL24, SFPARECIP, SFPGT, SFPLE, SFPMOV_CONFIG
#
# Reference: ttsim-analysis/ERRATA.md C-009 (BH-only instructions)
#            ttsim-analysis/ISA_SPEC.md Section 4.2

# CHECK: error:
# CHECK-SAME: instruction requires
sfpmul24 l0, l1, l9, l2, 0

# CHECK: error:
# CHECK-SAME: instruction requires
sfparecip l0, l1, 0, 0

# CHECK: error:
# CHECK-SAME: instruction requires
sfpgt l0, l1, 0, 0

# CHECK: error:
# CHECK-SAME: instruction requires
sfple l0, l1, 0, 0
