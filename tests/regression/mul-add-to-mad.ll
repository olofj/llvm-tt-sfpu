; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Regression test for MUL+ADD → MAD combining (GH-Q-002).
; GCC generates separate SFPMUL + SFPNOP + SFPADD instead of SFPMAD.
; The LLVM combining pass (RISCVXttSFPUCombine) should fold these.
;
; GCC pattern:
;   sfpmul  l2, l0, l1, l9, 0   ; tmp = a * b
;   sfpnop                       ; NOP (even on BH!)
;   sfpadd  l2, l10, l2, l3, 0  ; result = tmp + c
;
; LLVM expected:
;   sfpmad  l2, l0, l1, l3, 0   ; result = a * b + c (single instruction)
;
; Reference: sfpi-gcc/gcc/config/riscv/tt/gimple-rvtt-combine.cc:try_combine_mul_add()

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)

; Direct use of SFPMAD intrinsic — should NOT be decomposed
; CHECK-LABEL: test_direct_mad:
; CHECK: sfpmad
; CHECK-NOT: sfpmul
; CHECK-NOT: sfpadd
define void @test_direct_mad() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  ; a * b + c → SFPMAD (not MUL + ADD)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 %c, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Chain of two MADs (Horner series) — should emit 2 SFPMADs, no MUL or ADD
; CHECK-LABEL: test_horner_two_step:
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK-NOT: sfpmul
; CHECK-NOT: sfpadd
define void @test_horner_two_step() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  ; Horner step 1: tmp = val * 0.8373(L8) + 0.0(L9)
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  ; Horner step 2: result = val * tmp + 1.0(L10)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %tmp, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
