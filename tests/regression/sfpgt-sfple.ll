; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Regression test for GH-Q-005: BH should use SFPGT/SFPLE directly.
; GCC generates old WH sequence (sfpmad + 2x sfpsetcc) instead of using
; the BH-specific comparison instructions.
;
; Reference: ttsim-analysis/ERRATA.md C-009, GH-Q-005

target triple = "riscv32-unknown-unknown"

declare void @llvm.riscv.tt.sfpgt(i32, i32, i32)
declare void @llvm.riscv.tt.sfple(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)

; Direct SFPGT usage (BH-only) — should NOT decompose to sfpmad+sfpsetcc
; CHECK-LABEL: test_sfpgt:
; CHECK: sfpgt
; CHECK-NOT: sfpmad
; CHECK-NOT: sfpsetcc
define void @test_sfpgt() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpgt(i32 %a, i32 0, i32 0)
  ret void
}

; Direct SFPLE usage (BH-only) — should NOT decompose to sfpmad+sfpsetcc
; CHECK-LABEL: test_sfple:
; CHECK: sfple
; CHECK-NOT: sfpmad
; CHECK-NOT: sfpsetcc
define void @test_sfple() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfple(i32 %a, i32 0, i32 0)
  ret void
}
