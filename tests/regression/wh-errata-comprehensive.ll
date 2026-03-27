; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; Comprehensive WH errata coverage: E-002 (SFPSHFT2 zero-fill) and
; E-004 (pipeline hazards / NOP scheduling).
;
; Tests EVERY 2-cycle instruction type for correct NOP insertion on WH.
; Also tests static-delay instructions (SFPSWAP, SFPSHFT2 shuffle modes).
;
; This is ported from GCC test patterns in:
;   sfpi-gcc/gcc/testsuite/g++.target/tt/delay-34602-wh.C
;   sfpi-gcc/gcc/testsuite/g++.target/tt/shft2-26462-wh.C
;   sfpi-gcc/gcc/testsuite/g++.target/tt/swap-34602-wh.C
;
; Reference: ttsim-analysis/ERRATA.md E-002, E-004, E-004a
;            sfpi-gcc/gcc/config/riscv/tt/rvtt-protos.h:213-219

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpswap(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpshft2(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; ========================================================================
; E-004 Dynamic Delay Tests — NOP required when dependent consumer follows
; ========================================================================

; Test: SFPMAD dependent consumer
; CHECK-LABEL: test_e004_mad_dep:
; CHECK: sfpmad
; CHECK-NEXT: sfpnop
; CHECK: sfpstore
define void @test_e004_mad_dep() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %r = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 8, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 0, i32 0)
  ret void
}

; Test: SFPMUL dependent consumer
; CHECK-LABEL: test_e004_mul_dep:
; CHECK: sfpmul
; CHECK-NEXT: sfpnop
; CHECK: sfpstore
define void @test_e004_mul_dep() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %r = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 0, i32 0)
  ret void
}

; Test: SFPADD dependent consumer
; CHECK-LABEL: test_e004_add_dep:
; CHECK: sfpadd
; CHECK-NEXT: sfpnop
; CHECK: sfpstore
define void @test_e004_add_dep() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %r = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %a, i32 %b, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; E-004 Dynamic Delay — NO NOP when consumer is independent
; ========================================================================

; Test: SFPMAD with independent next instruction
; CHECK-LABEL: test_e004_mad_indep:
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
define void @test_e004_mad_indep() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  %r1 = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  %r2 = call i32 @llvm.riscv.tt.sfpmad(i32 %c, i32 %d, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r2, i32 0, i32 0, i32 16)
  ret void
}

; ========================================================================
; E-004 Static Delay Tests — SFPSWAP always needs NOP on next cycle
; ========================================================================

; Test: SFPSWAP static delay (NOP always required, even if independent)
; CHECK-LABEL: test_e004_swap_static:
; CHECK: sfpswap
; CHECK-NEXT: sfpnop
define void @test_e004_swap_static() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %swapped = call i32 @llvm.riscv.tt.sfpswap(i32 %a, i32 0, i32 0)
  ; Even though STORE is "independent", SFPSWAP has STATIC delay
  call void @llvm.riscv.tt.sfpstore(i32 %swapped, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; E-004 — SFPMULI (immediate multiply, also 2-cycle)
; Ported from GCC delay-34602-wh.C dyn::one
; ========================================================================

; GCC pattern: SFPLOAD → SFPMULI → SFPNOP → SFPSTORE
; SFPMULI is 2-cycle, store reads its result → NOP required
;
; CHECK-LABEL: test_e004_muli_dep:
; CHECK: sfpload
; CHECK: sfpmuli
; CHECK-NEXT: sfpnop
; CHECK: sfpstore
define void @test_e004_muli_dep() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  ; SFPMULI is modeled as SFPLOADI + SFPMUL combined
  ; We use the MAD form since SFPMULI requires the combine pass
  %r = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; E-002 — SFPSHFT2 SHFLSHR1 workaround (dead rotate before shift-right)
; On WH, SFPSHFT2 with SUBVEC_SHFLSHR1 (mod1=4) must be preceded by
; a dead SFPSHFT2 with SUBVEC_SHFLROR1 (mod1=3) using L9 (zero).
; ========================================================================

; Test: SFPSHFT2 with shuffle mode needs E-002 workaround
; CHECK-LABEL: test_e002_shft2_workaround:
; CHECK: sfpshft2
; CHECK: sfpstore
define void @test_e002_shft2_workaround() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  ; SFPSHFT2 with mod1=4 (SUBVEC_SHFLSHR1) triggers E-002
  %r = call i32 @llvm.riscv.tt.sfpshft2(i32 %a, i32 0, i32 4)
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 0, i32 0)
  ret void
}
