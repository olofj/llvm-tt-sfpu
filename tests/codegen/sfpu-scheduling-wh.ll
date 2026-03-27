; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH scheduling model verification: TensixWHModel.
; Tests that LLVM's PostRA scheduler handles WH's software pipeline management:
;
; On WH (unlike BH):
; - 2-cycle instructions need SFPNOP when consumer is dependent
; - Hardware does NOT scoreboard — the compiler is responsible
; - Independent work can fill delay slots (eliminating NOPs)
;
; This directly addresses GH-Q-006: "No Pipeline Model for Instruction
; Scheduling" — LLVM provides TensixWHModel while GCC has no pipeline model.
;
; Reference: ttsim-analysis/ERRATA.md E-004, GH-Q-001, GH-Q-006
;            RISCVSchedXttSFPU.td (TensixWHModel)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpdivp2(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Test 1: Two independent MADs — scheduler interleaves (no NOP).
; This is the key optimization: GCC inserts NOP here, LLVM should not.
;
; GCC output (bad):  sfpmad; sfpnop; sfpmad; sfpnop; sfpstore; sfpstore
; LLVM output (good): sfpmad; sfpmad; sfpnop; sfpstore; sfpstore
;
; CHECK-LABEL: test_wh_interleaved_mads:
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
define void @test_wh_interleaved_mads() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  %mad1 = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  %mad2 = call i32 @llvm.riscv.tt.sfpmad(i32 %c, i32 %d, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad1, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad2, i32 0, i32 0, i32 16)
  ret void
}

; Test 2: Dependent chain — NOP required between MAD and dependent MOV.
; On WH there is no scoreboarding, so the NOP is mandatory.
;
; CHECK-LABEL: test_wh_dependent_chain:
; CHECK: sfpmul
; CHECK-NEXT: sfpnop
; CHECK: sfpmov
define void @test_wh_dependent_chain() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %mul = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %mul, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: Realistic pattern — Horner series with interleaving opportunity.
; The loads for later stages can be interleaved into earlier MAD delay slots.
;
; The ideal schedule for a 2-step Horner with interleaved loads:
;   sfpload   (val from Dst)
;   sfpexexp  (extract exponent — 1 cycle)
;   sfpdivp2  (normalize — 1 cycle)
;   sfpmad    (Horner step 1 — 2 cycles)
;   sfpexexp  or sfploadi (FILLS DELAY SLOT — 1 cycle, independent)
;   sfpmad    (Horner step 2, uses step 1 result — 2 cycles)
;   sfpstore
;
; CHECK-LABEL: test_wh_horner_interleaved:
; CHECK: sfpload
; CHECK: sfpexexp
; CHECK: sfpdivp2
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpmad
define void @test_wh_horner_interleaved() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %val, i32 0, i32 0)
  %norm = call i32 @llvm.riscv.tt.sfpdivp2(i32 %val, i32 0, i32 0)
  %tmp = call i32 @llvm.riscv.tt.sfpmad(i32 %norm, i32 8, i32 9, i32 0)
  ; This exexp doesn't depend on %tmp — scheduler can interleave
  %exp2 = call i32 @llvm.riscv.tt.sfpexexp(i32 %norm, i32 0, i32 2)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %norm, i32 %tmp, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
