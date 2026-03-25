; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test _lv (live value) instruction variants for predicated regions.
; When a register is live across a v_if/v_endif boundary and written inside
; the predicated region, the _lv variant must be used to preserve per-lane
; values in disabled lanes.
;
; Based on the real reciprocal kernel pattern from ckernel_sfpu_recip.h:
;   sfpi::vFloat y = sfpi::approx_recip(x);
;   sfpi::vFloat t = x * y - sfpi::vConstFloatPrgm0;  // live across v_if
;   v_if (t < 0) {
;     y = y * -t - sfpi::vConst0;  // y is live — needs _lv variant
;   } v_endif;
;
; Reference: sfpi-gcc/gcc/config/riscv/tt/rvtt-insn.def (_lv variants)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad.lv(i32, i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul.lv(i32, i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov.lv(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfparecip(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)

; Reciprocal with predicated Newton-Raphson refinement.
; 'y' is live across the v_if — the refinement inside v_if must use _lv
; to preserve y in lanes where t >= 0 (condition false).
;
; CHECK-LABEL: test_recip_lv:
; CHECK: sfpload
; CHECK: sfparecip
; CHECK: sfpmad
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfppopc
; CHECK: sfpstore
define void @test_recip_lv() {
entry:
  ; x = load from Dst
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; y = approx_recip(x)
  %y = call i32 @llvm.riscv.tt.sfparecip(i32 %x, i32 0, i32 0)

  ; t = x * y - vConstFloatPrgm0 (L11 = -1.0 convention)
  %t = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 %y, i32 11, i32 0)

  ; v_if (t < 0)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %t, i32 0, i32 0)  ; LT0 mode

  ; y = y * -t - vConst0 (L9 = 0.0)
  ; This is inside v_if, and y is live across the boundary → need _lv
  %y_refined = call i32 @llvm.riscv.tt.sfpmad.lv(i32 %y, i32 %y, i32 %t, i32 9, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()

  ; Store result — y_refined in lanes where t < 0, original y otherwise
  call void @llvm.riscv.tt.sfpstore(i32 %y_refined, i32 0, i32 0, i32 0)
  ret void
}

; Simple _lv MOV test: copy inside predicated region
; CHECK-LABEL: test_mov_lv:
; CHECK: sfppushc
; CHECK: sfpmov
; CHECK: sfppopc
define i32 @test_mov_lv() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %src = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)

  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %src, i32 0, i32 0)

  ; val is live — use _lv variant
  %val_updated = call i32 @llvm.riscv.tt.sfpmov.lv(i32 %val, i32 %src, i32 0, i32 0)

  call void @llvm.riscv.tt.sfppopc()
  ret i32 %val_updated
}
