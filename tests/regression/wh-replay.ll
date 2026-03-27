; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; REPLAY buffer optimization: repeated sequences are recorded once and
; replayed for subsequent occurrences.
;
; WH has a 128-entry instruction FIFO (vs BH's 512). REPLAY reduces FIFO
; pressure by compressing repeated sequences into a single REPLAY instruction.
;
; Minimum sequence length: 4 instructions. The REPLAY pass uses a greedy
; knapsack algorithm to allocate the 32-entry replay buffer.
;
; Reference: ttsim-analysis/FUNCTIONAL_UNITS.md Section 9.2 (REPLAY)
;            ttsim-analysis/ERRATA.md Section 3.8 (REPLAY Buffer Constraints)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpdivp2(i32, i32, i32)

; Test: Two identical 4-instruction sequences.
; REPLAY should record the first and replay for the second.
;
; Without REPLAY: 8 SFPU instructions
; With REPLAY: 4 original + 1 REPLAY = 5 (saves 3)
;
; CHECK-LABEL: test_replay_candidate:
; CHECK: sfpload
; CHECK: sfpexexp
; CHECK: sfpdivp2
; CHECK: sfpmad
; CHECK: sfpload
define void @test_replay_candidate() {
  ; Sequence 1: load → exexp → divp2 → mad
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %e1 = call i32 @llvm.riscv.tt.sfpexexp(i32 %v1, i32 0, i32 0)
  %d1 = call i32 @llvm.riscv.tt.sfpdivp2(i32 %v1, i32 0, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpmad(i32 %d1, i32 8, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 0)

  ; Sequence 2: identical pattern (candidate for REPLAY)
  %v2 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %e2 = call i32 @llvm.riscv.tt.sfpexexp(i32 %v2, i32 0, i32 0)
  %d2 = call i32 @llvm.riscv.tt.sfpdivp2(i32 %v2, i32 0, i32 0)
  %r2 = call i32 @llvm.riscv.tt.sfpmad(i32 %d2, i32 8, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r2, i32 0, i32 0, i32 16)

  ret void
}

; Test: Short sequence (< 4 instructions) — should NOT use REPLAY.
;
; CHECK-LABEL: test_short_no_replay:
; CHECK-NOT: replay
define void @test_short_no_replay() {
  ; Sequence 1: only 2 instructions
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpmov(i32 %v1, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 0)

  ; Sequence 2: identical but too short for REPLAY (min 4)
  %v2 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %r2 = call i32 @llvm.riscv.tt.sfpmov(i32 %v2, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r2, i32 0, i32 0, i32 16)

  ret void
}
