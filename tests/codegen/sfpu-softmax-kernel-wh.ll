; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH Softmax kernel — the most common SFPU workload.
; Same IR as sfpu-softmax-kernel.ll but targeting WH.
;
; Key WH differences from BH:
; 1. NOPs required after dependent 2-cycle instructions
; 2. No BH-only instructions (sfparecip etc.) in output
; 3. C-010: dst=src_a constraint on arithmetic
;
; Reference: ttsim-analysis/ERRATA.md E-004, C-010
;            tt-metal/tt_llk_wormhole_b0/common/inc/sfpu/ckernel_sfpu_exp.h

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpdivp2(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Single-row softmax core.
; Verify:
; - Correct instruction selection on WH
; - No BH-only instructions
; - NOPs where needed (dependent MADs)
;
; CHECK-LABEL: softmax_exp_row:
; CHECK: sfpload
; CHECK: sfpexexp
; CHECK: sfpdivp2
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK-NOT: sfparecip
; CHECK-NOT: sfpmul24
; CHECK: sfpstore
define void @softmax_exp_row(i32 %max_exp) {
entry:
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %val, i32 0, i32 0)
  %norm = call i32 @llvm.riscv.tt.sfpdivp2(i32 %val, i32 0, i32 0)
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %norm, i32 8, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %norm, i32 %tmp, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Two-row softmax — tests scheduler interleaving across independent data.
; The scheduler should overlap row0 and row1 MADs to fill delay slots.
;
; CHECK-LABEL: softmax_two_rows:
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfpstore
; CHECK: sfpstore
define void @softmax_two_rows() {
entry:
  ; Row 0
  %val0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  ; Row 1
  %val1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)

  ; Horner step 1 for row 0 and row 1 (independent)
  %tmp0 = call i32 @llvm.riscv.tt.sfpmad(i32 %val0, i32 8, i32 9, i32 0)
  %tmp1 = call i32 @llvm.riscv.tt.sfpmad(i32 %val1, i32 8, i32 9, i32 0)

  ; Horner step 2 for row 0 and row 1 (dependent on step 1 of same row)
  %res0 = call i32 @llvm.riscv.tt.sfpmad(i32 %val0, i32 %tmp0, i32 10, i32 0)
  %res1 = call i32 @llvm.riscv.tt.sfpmad(i32 %val1, i32 %tmp1, i32 10, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %res0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %res1, i32 0, i32 0, i32 16)
  ret void
}

; Softmax with predication (v_if/v_else/v_endif).
; Verifies CC stack operations work correctly on WH target.
;
; CHECK-LABEL: softmax_with_predication:
; CHECK: sfpload
; CHECK: sfpexexp
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfppopc
; CHECK: sfpstore
define void @softmax_with_predication() {
entry:
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %val, i32 0, i32 2)

  ; v_if (exp >= 0)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %exp, i32 0, i32 4)

  ; Process only lanes where exp >= 0
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()

  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
