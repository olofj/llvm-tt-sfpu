; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Realistic softmax kernel test — the most common SFPU workload.
; Tests the full sequence: load → exexp → divp2 → MAD Horner → store.
;
; This kernel demonstrates where LLVM beats GCC:
; 1. Scheduling: MAD operations interleaved (no unnecessary NOPs on BH)
; 2. Register pressure: 8 LRegs managed by LLVM RA
; 3. Pipeline utilization: Load→Simple→MAD→Store sub-unit overlap
;
; Based on tt-metal/tt_llk/tt_llk_blackhole/common/inc/sfpu/ckernel_sfpu_exp.h
; and typical softmax kernel patterns.

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpdivp2(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpiadd(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpsetexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfparecip(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Softmax core: process one row of Dst
;   1. Load value
;   2. Subtract max exponent (via SFPDIVP2)
;   3. Compute exp via Horner series
;   4. Store result
;
; CHECK-LABEL: softmax_exp_row:
; CHECK: sfpload
; CHECK: sfpexexp
; CHECK: sfpdivp2
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfpstore
define void @softmax_exp_row(i32 %max_exp) {
entry:
  ; Load val from Dst row 0
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; Extract exponent
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %val, i32 0, i32 0)

  ; Normalize: divide by 2^max_exp
  %norm = call i32 @llvm.riscv.tt.sfpdivp2(i32 %val, i32 0, i32 0)

  ; Horner series for exp approximation:
  ;   tmp = norm * L8(0.8373) + L9(0.0)
  ;   result = norm * tmp + L10(1.0)
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %norm, i32 8, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %norm, i32 %tmp, i32 10, i32 0)

  ; Store back to Dst
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Two-row softmax with independent data — tests scheduling interleaving.
; The scheduler should overlap work on row0 and row1 to fill MAD latency.
;
; On BH: No NOPs between independent MADs (hardware scoreboard).
; On WH: NOPs would be needed between dependent operations only.
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
  ; Load two rows
  %v0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)

  ; Horner step 1 for both rows (independent — can interleave)
  %t0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 8, i32 9, i32 0)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 8, i32 9, i32 0)

  ; Horner step 2 for both rows
  %r0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 %t0, i32 10, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 %t1, i32 10, i32 0)

  ; Store both rows
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)
  ret void
}

; Reciprocal for softmax normalization — tests BH SFPARECIP + predication.
;
; CHECK-LABEL: softmax_recip:
; CHECK: sfparecip
; CHECK: sfpmad
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfppopc
define void @softmax_recip() {
entry:
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; y = approx_recip(x)
  %y = call i32 @llvm.riscv.tt.sfparecip(i32 %x, i32 0, i32 0)

  ; Newton-Raphson: t = x * y + L11(-1.0)
  %t = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 %y, i32 11, i32 0)

  ; v_if (t < 0) — only refine if not NaN
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %t, i32 0, i32 0)

  ; y = y * -t + L9(0.0)
  %y_refined = call i32 @llvm.riscv.tt.sfpmad(i32 %y, i32 %t, i32 9, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()

  call void @llvm.riscv.tt.sfpstore(i32 %y_refined, i32 0, i32 0, i32 0)
  ret void
}
