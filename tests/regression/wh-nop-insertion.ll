; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH E-004 correctness: NOP MUST be inserted after 2-cycle instructions
; when the next SFPU instruction is data-dependent.
;
; On WH, there is no hardware scoreboarding — software must manage pipeline
; hazards by inserting SFPNOP. This is the most critical WH correctness test.
;
; Reference: ttsim-analysis/ERRATA.md E-004 (SFPU Pipeline Hazards)
;            ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.1 (MAD: 2 cycles)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Test 1: Dependent MAD → MOV chain requires NOP on WH.
; The MOV reads the result of MAD, which takes 2 cycles.
; Without a NOP, the MOV would read stale data.
;
; CHECK-LABEL: test_wh_mad_dependent_mov:
; CHECK: sfpmad
; CHECK-NEXT: sfpnop
; CHECK-NEXT: sfpmov
define void @test_wh_mad_dependent_mov() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %mad = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  ; Dependent: MOV reads %mad result
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %mad, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: Dependent MUL → STORE chain requires NOP on WH.
;
; CHECK-LABEL: test_wh_mul_dependent_store:
; CHECK: sfpmul
; CHECK-NEXT: sfpnop
; CHECK-NEXT: sfpstore
define void @test_wh_mul_dependent_store() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %mul = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  ; Dependent: STORE reads %mul result
  call void @llvm.riscv.tt.sfpstore(i32 %mul, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: Dependent ADD → MAD chain requires NOP on WH.
; The second MAD uses the result of ADD.
;
; CHECK-LABEL: test_wh_add_dependent_mad:
; CHECK: sfpadd
; CHECK-NEXT: sfpnop
; CHECK: sfpmad
define void @test_wh_add_dependent_mad() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %add = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %a, i32 %b, i32 0)
  ; Dependent: MAD reads %add as src_a
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %add, i32 %c, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 4: Dependent Horner chain — each MAD depends on the previous.
; Every MAD→MAD dependency needs a NOP in between on WH.
;
; CHECK-LABEL: test_wh_horner_chain:
; CHECK: sfpmad
; CHECK-NEXT: sfpnop
; CHECK: sfpmad
; CHECK-NEXT: sfpnop
; CHECK: sfpmad
define void @test_wh_horner_chain() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  ; Horner step 1: tmp1 = val * L8(0.8373) + L9(0.0)
  %tmp1 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  ; Horner step 2: tmp2 = val * tmp1 + L10(1.0) — depends on tmp1
  %tmp2 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %tmp1, i32 10, i32 0)
  ; Horner step 3: result = val * tmp2 + L10(1.0) — depends on tmp2
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %tmp2, i32 10, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
