; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH delay slot optimization: when independent work is available, the scheduler
; should interleave it into the delay slot after a 2-cycle instruction,
; ELIMINATING the NOP entirely.
;
; This is the primary optimization opportunity for WH (15-25% improvement).
; GCC never does this — it always inserts NOPs. LLVM's PostRA scheduler can
; reorder independent instructions to fill the latency gap.
;
; Reference: ttsim-analysis/ERRATA.md GH-Q-001, GH-Q-006
;            ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.1

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)

; Test 1: Two independent MADs — second can fill first's delay slot.
; No NOP needed because the second MAD doesn't read the first MAD's result.
;
; CHECK-LABEL: test_wh_two_independent_mads:
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
define void @test_wh_two_independent_mads() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  ; Independent: mad1 and mad2 have no data dependency
  %mad1 = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  %mad2 = call i32 @llvm.riscv.tt.sfpmad(i32 %c, i32 %d, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad1, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad2, i32 0, i32 0, i32 16)
  ret void
}

; Test 2: Load interleaved into MAD delay slot.
; Pattern from GH-Q-001: load can fill the gap between MAD and its consumer.
;
; GCC (bad):  sfpmad; sfpnop; sfpmad    (3 cycles wasted)
; LLVM (good): sfpmad; sfploadi; sfpmad  (0 cycles wasted)
;
; CHECK-LABEL: test_wh_load_fills_delay:
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpmad
define void @test_wh_load_fills_delay() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  ; Load a constant needed later — scheduler can move this between the MADs
  %coeff = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  ; MAD step 1: uses %val
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  ; MAD step 2: uses %tmp (dependent!) but %coeff load can fill the gap
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %tmp, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: MOV fills MAD delay slot (MOV is 1-cycle, independent of MAD result).
;
; CHECK-LABEL: test_wh_mov_fills_delay:
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpmov
define void @test_wh_mov_fills_delay() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %mad = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  ; Independent MOV can fill the delay slot
  %copy = call i32 @llvm.riscv.tt.sfpmov(i32 %c, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %copy, i32 0, i32 0, i32 16)
  ret void
}
