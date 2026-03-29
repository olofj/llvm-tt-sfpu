; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test for RISCVXttSFPUPeephole EXEXP+SETCC fusion.
;
; When SFPEXEXP is immediately followed by SFPSETCC on the same register,
; the peephole fuses them into a single SFPEXEXP with CC-setting mode:
;   EXEXP(0) + SETCC(LT0)  → EXEXP(SET_CC_SGN_EXP = 2)
;   EXEXP(0) + SETCC(COMP) → EXEXP(SET_CC_COMP_EXP = 8)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)

; SFPEXEXP + SFPSETCC on same register: should fuse
;
; CHECK-LABEL: test_exexp_setcc_fuse:
; CHECK: sfpexexp
; CHECK-NOT: sfpsetcc
define void @test_exexp_setcc_fuse() {
entry:
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %e = call i32 @llvm.riscv.tt.sfpexexp(i32 %a, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpsetcc(i32 %e, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %e, i32 0, i32 7, i32 0)
  ret void
}
