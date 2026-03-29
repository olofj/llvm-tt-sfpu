; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test for RISCVXttSFPUSynth pass: immediate overflow synthesis.
;
; When an immediate exceeds the instruction's field width, the synth pass
; inserts SFPLOADI to load the constant, then substitutes the register-form
; instruction variant (SFPMULI → SFPMUL, SFPADDI → SFPADD).

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfpmuli(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpaddi(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)

; Within-range immediate (16-bit): should use SFPMULI directly
;
; CHECK-LABEL: test_muli_in_range:
; CHECK: sfpmuli
; CHECK-NOT: sfploadi
define void @test_muli_in_range() {
entry:
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %r = call i32 @llvm.riscv.tt.sfpmuli(i32 %a, i32 1000, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 7, i32 0)
  ret void
}

; Within-range SFPADDI
;
; CHECK-LABEL: test_addi_in_range:
; CHECK: sfpaddi
; CHECK-NOT: sfploadi{{.*}}42
define void @test_addi_in_range() {
entry:
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %r = call i32 @llvm.riscv.tt.sfpaddi(i32 %a, i32 42, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 7, i32 0)
  ret void
}
