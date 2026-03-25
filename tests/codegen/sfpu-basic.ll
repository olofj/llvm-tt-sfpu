; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test basic SFPU codegen: intrinsic → instruction selection.
; Verifies that LLVM intrinsics lower to the correct SFPU instructions.

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Basic load → multiply → add → store sequence
; CHECK-LABEL: test_load_mad_store:
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpmad
; CHECK: sfpstore
define void @test_load_mad_store() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %c, i32 0, i32 0, i32 0)
  ret void
}

; Verify MOV instruction selection
; CHECK-LABEL: test_mov:
; CHECK: sfpmov
define i32 @test_mov(i32 %src) {
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %src, i32 0, i32 0)
  ret i32 %result
}

; Verify NOP insertion
; CHECK-LABEL: test_nop:
; CHECK: sfpnop
define void @test_nop() {
  call void @llvm.riscv.tt.sfpnop()
  ret void
}

; Multiply followed by add — scheduler should not need NOP on BH
; CHECK-LABEL: test_mul_add_independent:
; CHECK: sfpmul
; CHECK-NOT: sfpnop
; CHECK: sfpadd
define void @test_mul_add_independent() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  ; These are independent — no data dependency
  %mul = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %add = call i32 @llvm.riscv.tt.sfpadd(i32 %c, i32 %d, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mul, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %add, i32 0, i32 0, i32 16)
  ret void
}
