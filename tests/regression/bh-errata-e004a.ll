; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test for BH-specific E-004a scoreboard errata.
;
; On Blackhole, the hardware scoreboard fails to detect certain producer/consumer
; combinations. When a 2-cycle instruction (SFPMAD/SFPMUL/SFPADD) produces a
; result, and the consumer is an E-004a errata instruction (SFPIADD, SFPSHFT,
; etc.), the errata pass must insert an SFPNOP between them.
;
; Non-errata consumers (e.g., SFPSTORE, another SFPMAD) should NOT get NOPs.

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpiadd(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)

; SFPMAD → SFPIADD: errata case, needs NOP
;
; CHECK-LABEL: test_mad_iadd_errata:
; CHECK: sfpmad
; CHECK-NEXT: sfpnop
; CHECK-NEXT: sfpiadd
define void @test_mad_iadd_errata() {
entry:
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %b = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16384)
  %m = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  %r = call i32 @llvm.riscv.tt.sfpiadd(i32 %m, i32 5, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 7, i32 0)
  ret void
}

; SFPMAD → SFPSTORE: NOT errata, no NOP needed
;
; CHECK-LABEL: test_mad_store_no_errata:
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpstore
define void @test_mad_store_no_errata() {
entry:
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %b = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16384)
  %m = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %m, i32 0, i32 7, i32 0)
  ret void
}
