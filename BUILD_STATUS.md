TableGen: PASSES
llvm-mc: BUILT AND WORKING
All 9 encoding tests pass — byte-identical to GCC sfpu-ops-bh.h

Binary: llvm-project-upstream/build/bin/llvm-mc
Test: echo 'sfpmad l0, l1, l2, l3, 0' | llvm-mc -triple riscv32 -mattr=+xttsfpu,+xttsfpu-bh --show-encoding
