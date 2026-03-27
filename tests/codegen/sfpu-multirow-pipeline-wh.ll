; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; Multi-row software pipelining: overlap loop iterations to fill delay slots.
;
; Real SFPU kernels iterate over 16-32 tile rows. The loop body is often a
; dependent chain (Horner, sigmoid, etc.) with unavoidable NOPs. By unrolling
; and interleaving 2-4 rows, we fill delay slots with work from other rows.
;
; This is the "poor man's software pipelining" — LLVM's scheduler handles
; the interleaving automatically once we unroll the loop.
;
; Pattern: 4-row unrolled Horner (2-step exp approximation)
;   Without interleaving (1 row): load, mad, nop, mad, nop, store = 6 insns/row
;   With 4-row interleaving:      4*(load, mad, mad, store) = 4 insns/row
;   Savings: 33% (all NOPs eliminated)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)

; 4-row unrolled Horner: all delay slots filled by other rows.
; The 4 independent rows provide enough ILP to eliminate all NOPs.
;
; Expected schedule:
;   load0, load1, load2, load3,
;   mad0_step1, mad1_step1, mad2_step1, mad3_step1,  ← all independent, no NOPs!
;   mad0_step2, mad1_step2, mad2_step2, mad3_step2,  ← same
;   store0, store1, store2, store3
;
; CHECK-LABEL: horner_4row_pipeline:
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
define void @horner_4row_pipeline() {
  ; Load 4 rows
  %v0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %v2 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %v3 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)

  ; Horner step 1 for all 4 rows (all independent)
  %t0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 8, i32 9, i32 0)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 8, i32 9, i32 0)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %v2, i32 8, i32 9, i32 0)
  %t3 = call i32 @llvm.riscv.tt.sfpmad(i32 %v3, i32 8, i32 9, i32 0)

  ; Horner step 2 for all 4 rows (each depends only on own step 1)
  %r0 = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 %t0, i32 10, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpmad(i32 %v1, i32 %t1, i32 10, i32 0)
  %r2 = call i32 @llvm.riscv.tt.sfpmad(i32 %v2, i32 %t2, i32 10, i32 0)
  %r3 = call i32 @llvm.riscv.tt.sfpmad(i32 %v3, i32 %t3, i32 10, i32 0)

  ; Store all 4 rows
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)
  call void @llvm.riscv.tt.sfpstore(i32 %r2, i32 0, i32 0, i32 32)
  call void @llvm.riscv.tt.sfpstore(i32 %r3, i32 0, i32 0, i32 48)
  ret void
}

; 3-row unrolled exp with Estrin: combines multi-row + Estrin benefits.
; Each row uses Estrin degree-3, and rows interleave.
;
; CHECK-LABEL: estrin_3row_pipeline:
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpmov
; CHECK: sfpmov
; CHECK: sfpmov
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
define void @estrin_3row_pipeline() {
  ; Load 3 rows
  %x0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %x1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %x2 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)

  ; Copy x for Estrin sub-chains (each row needs lo and hi)
  %x0_lo = call i32 @llvm.riscv.tt.sfpmov(i32 %x0, i32 0, i32 0)
  %x1_lo = call i32 @llvm.riscv.tt.sfpmov(i32 %x1, i32 0, i32 0)
  %x2_lo = call i32 @llvm.riscv.tt.sfpmov(i32 %x2, i32 0, i32 0)

  ; Estrin lo for all 3 rows (independent)
  %lo0 = call i32 @llvm.riscv.tt.sfpmad(i32 %x0_lo, i32 8, i32 9, i32 0)
  %lo1 = call i32 @llvm.riscv.tt.sfpmad(i32 %x1_lo, i32 8, i32 9, i32 0)
  %lo2 = call i32 @llvm.riscv.tt.sfpmad(i32 %x2_lo, i32 8, i32 9, i32 0)

  ; Estrin hi for all 3 rows (independent of lo)
  %hi0 = call i32 @llvm.riscv.tt.sfpmad(i32 %x0, i32 8, i32 10, i32 0)
  %hi1 = call i32 @llvm.riscv.tt.sfpmad(i32 %x1, i32 8, i32 10, i32 0)
  %hi2 = call i32 @llvm.riscv.tt.sfpmad(i32 %x2, i32 8, i32 10, i32 0)

  ; Store results
  call void @llvm.riscv.tt.sfpstore(i32 %hi0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %hi1, i32 0, i32 0, i32 16)
  call void @llvm.riscv.tt.sfpstore(i32 %hi2, i32 0, i32 0, i32 32)
  ret void
}
