; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH MUL+ADD → MAD combining (GH-Q-002 fix).
;
; On WH, the unfused sequence costs 4 cycles:
;   SFPMUL (2c) + SFPNOP (1c) + SFPADDI (1c) = 4 cycles
;
; The fused MAD sequence costs 3 cycles:
;   SFPLOADI (1c) + SFPMAD (2c) = 3 cycles (+ possible NOP)
;
; LLVM's combine pass should fuse MUL+ADD into MAD when profitable.
; The fused MAD must satisfy C-010 (dst=src_a).
;
; Reference: ttsim-analysis/ERRATA.md GH-Q-002
;            RISCVXttSFPUCombine.cpp

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)

; Test 1: Simple MUL followed by ADD of result — should fuse to MAD.
;
; Before combining:
;   sfpmul %tmp, %a, %b, L9, 0
;   sfpadd %result, L10, %tmp, %c, 0
;
; After combining:
;   sfpmad %result, %a, %b, %c, 0
;
; CHECK-LABEL: test_wh_mul_add_to_mad:
; CHECK: sfpmad
; CHECK-NOT: sfpmul
; CHECK-NOT: sfpadd
; CHECK: sfpstore
define void @test_wh_mul_add_to_mad() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  ; MUL then ADD — combine should fuse
  %tmp = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %tmp, i32 %c, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: MUL result used twice — cannot fuse (MUL has multiple uses).
;
; CHECK-LABEL: test_wh_mul_multi_use_no_fuse:
; CHECK: sfpmul
; CHECK: sfpstore
; CHECK: sfpstore
define void @test_wh_mul_multi_use_no_fuse() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %tmp = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %tmp, i32 %c, i32 0)
  ; tmp is used in both ADD and a direct store → cannot fuse
  call void @llvm.riscv.tt.sfpstore(i32 %tmp, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 16)
  ret void
}
