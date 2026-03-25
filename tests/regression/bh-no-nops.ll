; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Regression test for GH-CC-008: BH should NOT generate unnecessary NOPs.
; GCC inserts NOPs after 2-cycle instructions even on BH, which has hardware
; scoreboarding. LLVM's TensixBHModel knows that BH stalls automatically.
;
; Reference: ttsim-analysis/ERRATA.md E-004 (BH has hardware scoreboarding)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)

; On BH, a MUL followed by a dependent MOV should NOT have a NOP between them.
; The hardware scoreboard will stall the pipeline automatically.
;
; CHECK-LABEL: test_bh_no_nop_after_mul:
; CHECK: sfpmul
; CHECK-NOT: sfpnop
; CHECK: sfpmov
define void @test_bh_no_nop_after_mul() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %mul = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %mul, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Multiple back-to-back 2-cycle operations: no NOPs on BH.
; CHECK-LABEL: test_bh_no_nop_chain:
; CHECK: sfpmul
; CHECK-NEXT: sfpmul
; CHECK-NOT: sfpnop
define void @test_bh_no_nop_chain() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  ; Two independent multiplies — no NOP needed
  %mul1 = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %mul2 = call i32 @llvm.riscv.tt.sfpmul(i32 %c, i32 %d, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mul1, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mul2, i32 0, i32 0, i32 16)
  ret void
}
