; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH C-010 constraint enforcement: for SFPMUL, SFPMAD, SFPADD, the
; destination register must equal src_a.
;
; This constraint does not exist on BH (where dst can be any register).
; Incorrect enforcement would produce wrong results on silicon — the
; hardware ignores the dst field and always writes to src_a.
;
; Reference: ttsim-analysis/ERRATA.md C-010
;            RISCVXttSFPUConstraints.cpp

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Test 1: SFPMAD — dst must equal src_a
; The assembler output should show the same register for dst and the first
; source operand. FileCheck regex captures the register name.
;
; CHECK-LABEL: test_wh_mad_constraint:
; CHECK: sfpmad [[R:l[0-7]]], [[R]],
define void @test_wh_mad_constraint() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: SFPMUL — dst must equal src_a, and src_c must be L9 (zero)
;
; CHECK-LABEL: test_wh_mul_constraint:
; CHECK: sfpmul [[R:l[0-7]]], [[R]],
define void @test_wh_mul_constraint() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %result = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: Multiple arithmetic ops — each must independently satisfy C-010.
; Verify the constraint holds across a sequence of operations.
;
; CHECK-LABEL: test_wh_multiple_constraints:
; CHECK: sfpmul [[R1:l[0-7]]], [[R1]],
; CHECK: sfpmad [[R2:l[0-7]]], [[R2]],
define void @test_wh_multiple_constraints() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %mul = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %mad = call i32 @llvm.riscv.tt.sfpmad(i32 %c, i32 %mul, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad, i32 0, i32 0, i32 0)
  ret void
}
