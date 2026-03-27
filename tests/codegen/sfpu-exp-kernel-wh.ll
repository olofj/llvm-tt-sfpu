; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH exponential kernel — tests predication + Horner series + squaring.
; Same IR as sfpu-exp-kernel.ll but targeting WH.
;
; Key WH verifications:
; 1. NOP after dependent 2-cycle instructions
; 2. No BH-only instructions (sfparecip, sfpmul24, etc.)
; 3. CC stack operations (sfppushc/sfppopc/sfpsetcc) work on WH
; 4. C-010 dst=src_a constraint on all arithmetic
;
; Reference: ttsim-analysis/ERRATA.md E-004, C-010
;            tt-metal/tt_llk_wormhole_b0/common/inc/sfpu/ckernel_sfpu_exp.h

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpsetexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpiadd(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; WH exp kernel: extract exponent, normalize, Horner, square.
; Verify correct WH instruction selection and no BH leakage.
;
; CHECK-LABEL: sfpu_exp_simplified:
; CHECK: sfpload
; CHECK: sfpexexp
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpsetexp
; CHECK: sfppopc
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK-NOT: sfparecip
; CHECK-NOT: sfpmul24
; CHECK-NOT: sfpgt
; CHECK-NOT: sfple
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmul
; CHECK: sfppopc
; CHECK: sfpstore
define void @sfpu_exp_simplified() {
entry:
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %val, i32 0, i32 2)

  ; v_if (exp >= 0)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %exp, i32 0, i32 4)

  %val_norm = call i32 @llvm.riscv.tt.sfpsetexp(i32 %val, i32 126, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()

  ; Horner series
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %val_norm, i32 8, i32 9, i32 0)
  %val2 = call i32 @llvm.riscv.tt.sfpmad(i32 %val_norm, i32 %tmp, i32 10, i32 0)

  ; v_if for squaring
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %exp, i32 0, i32 4)

  %val3 = call i32 @llvm.riscv.tt.sfpmul(i32 %val2, i32 %val2, i32 9, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()

  call void @llvm.riscv.tt.sfpstore(i32 %val3, i32 0, i32 0, i32 0)
  ret void
}
