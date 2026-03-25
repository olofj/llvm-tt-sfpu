; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Regression test for GH-Q-002: FMA codegen optimization.
; GCC generates separate MUL + ADD instead of a single MAD.
; LLVM should combine a*b+c into SFPMAD when all operands are available.
;
; Reference: ttsim-analysis/ERRATA.md GH-Q-002

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)

; Direct MAD: should emit SFPMAD, not SFPMUL + SFPADD.
; CHECK-LABEL: test_fma_direct:
; CHECK: sfpmad
; CHECK-NOT: sfpmul
; CHECK-NOT: sfpadd
define void @test_fma_direct() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 %c, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
