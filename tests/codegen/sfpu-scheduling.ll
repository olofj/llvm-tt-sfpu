; RUN: %llc %sfpu-bh-flags -pre-RA-sched=list-ilp %s -o - | %FileCheck %s
;
; Test that the LLVM MachineScheduler correctly handles SFPU latencies.
; On BH, 2-cycle instructions should have independent work interleaved
; (no NOPs needed due to hardware scoreboarding).
;
; This test directly addresses GH-Q-006: "No Pipeline Model for Instruction
; Scheduling" — LLVM's scheduler uses TensixBHModel to fill latency slots.
;
; Reference: ttsim-analysis/ERRATA.md E-004, I-005

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)

; Two independent MAD operations — scheduler should interleave them.
; The 2-cycle latency of the first MAD should be filled by the second MAD
; (or other independent work), not by a NOP.
;
; CHECK-LABEL: test_interleaved_mads:
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpmad
define void @test_interleaved_mads() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)

  ; Two independent MADs — scheduler should interleave
  %mad1 = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  %mad2 = call i32 @llvm.riscv.tt.sfpmad(i32 %c, i32 %d, i32 9, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %mad1, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mad2, i32 0, i32 0, i32 16)
  ret void
}

; Dependent chain: load → mul → add (uses mul result).
; On BH, hardware scoreboarding handles the 2-cycle mul latency.
; Scheduler should NOT insert NOP between mul and dependent add.
;
; CHECK-LABEL: test_dependent_chain:
; CHECK: sfpmul
; CHECK-NEXT: sfpmov
; CHECK: sfpstore
define void @test_dependent_chain() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)

  %mul = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  ; On BH, hardware will stall if result not ready — no NOP needed
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %mul, i32 0, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
