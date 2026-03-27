; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Realistic test: SFPU tanh kernel based on BH LUT pipeline.
; Tests the LUT instruction path: SFPLOADI to load coefficients,
; SFPLOAD from Dst, SFPLUT lookup, SFPSTORE back to Dst.
;
; tanh(x) on Tenstorrent SFPU uses a 3-coefficient LUT approach:
;   1. Load LUT coefficients into LRegs via SFPLOADI (imm16)
;   2. For each tile row: SFPLOAD from Dst, SFPLUT, SFPSTORE to Dst
;
; This exercises:
; - SFPLOADI: load BFloat16 immediate into LReg (LUT coefficient setup)
; - SFPLUT: hardware lookup-table evaluation using loaded coefficients
; - SFPLOAD/SFPSTORE: Dst <-> LReg transfer in the compute loop
; - SFPMAD: fused multiply-add for polynomial refinement
; - Loop structure with multiple SFPLUT calls
;
; Reference: tt-metal LLK ckernel_sfpu_tanh.h

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfplut(i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Load 3 LUT coefficients, then loop: load -> lut -> store
;
; CHECK-LABEL: sfpu_tanh_lut:
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfpload
; CHECK: sfplut
; CHECK: sfpstore
define void @sfpu_tanh_lut() {
entry:
  ; Load LUT coefficients into L0, L1, L2
  ; These represent the piecewise-linear tanh approximation slopes/offsets.
  ; coeff0 = BF16 0x3F00 (0.5)
  ; coeff1 = BF16 0x3E80 (0.25)
  ; coeff2 = BF16 0x3F80 (1.0)
  %c0 = call i32 @llvm.riscv.tt.sfploadi(i32 16128, i32 0)
  %c1 = call i32 @llvm.riscv.tt.sfploadi(i32 16000, i32 0)
  %c2 = call i32 @llvm.riscv.tt.sfploadi(i32 16256, i32 0)

  ; Load input from Dst row 0
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; LUT lookup: uses L0,L1,L2 as coefficients, val as input
  ; The SFPLUT instruction reads from LRegs set up by SFPLOADI
  %lut_result = call i32 @llvm.riscv.tt.sfplut(i32 0, i32 0)

  ; Store result back to Dst row 0
  call void @llvm.riscv.tt.sfpstore(i32 %lut_result, i32 0, i32 0, i32 0)

  ret void
}

; Full tanh with refinement: LUT + MAD correction pass
;
; CHECK-LABEL: sfpu_tanh_refined:
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfpload
; CHECK: sfplut
; CHECK: sfpmad
; CHECK: sfpstore
define void @sfpu_tanh_refined() {
entry:
  ; LUT coefficient setup (same as above)
  %c0 = call i32 @llvm.riscv.tt.sfploadi(i32 16128, i32 0)
  %c1 = call i32 @llvm.riscv.tt.sfploadi(i32 16000, i32 0)
  %c2 = call i32 @llvm.riscv.tt.sfploadi(i32 16256, i32 0)

  ; Load from Dst
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; LUT lookup
  %lut_out = call i32 @llvm.riscv.tt.sfplut(i32 0, i32 0)

  ; Polynomial refinement: result = lut_out * val + correction
  ; Uses L9 (CREG 0.0) as addend for simple multiply, L10 (CREG 1.0)
  %refined = call i32 @llvm.riscv.tt.sfpmad(i32 %lut_out, i32 %val, i32 10, i32 0)

  ; Store refined tanh result
  call void @llvm.riscv.tt.sfpstore(i32 %refined, i32 0, i32 0, i32 0)

  ret void
}

; Multi-row tanh: processes 2 Dst rows with LUT
;
; CHECK-LABEL: sfpu_tanh_multirow:
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfpload
; CHECK: sfplut
; CHECK: sfpstore
; CHECK: sfpload
; CHECK: sfplut
; CHECK: sfpstore
define void @sfpu_tanh_multirow() {
entry:
  ; LUT setup (once per kernel invocation)
  %c0 = call i32 @llvm.riscv.tt.sfploadi(i32 16128, i32 0)
  %c1 = call i32 @llvm.riscv.tt.sfploadi(i32 16000, i32 0)
  %c2 = call i32 @llvm.riscv.tt.sfploadi(i32 16256, i32 0)

  ; Row 0
  %v0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %r0 = call i32 @llvm.riscv.tt.sfplut(i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)

  ; Row 1 (addr=16 = next Dst row on BH)
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %r1 = call i32 @llvm.riscv.tt.sfplut(i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)

  ret void
}
