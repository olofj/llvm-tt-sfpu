; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH comparison synthesis: how comparisons are generated without SFPGT/SFPLE.
;
; On BH: x > 0 → SFPGT (1 instruction, 1 cycle)
; On WH: x > 0 → SFPSETCC(GTE0) + SFPSETCC(NE0) (2 instructions, 2 cycles)
;        x >= 0 → SFPSETCC(GTE0) (1 instruction, 1 cycle)
;        x < 0  → SFPSETCC(LT0) (1 instruction, 1 cycle)
;        x == 0 → SFPSETCC(EQ0) (1 instruction, 1 cycle)
;        x != 0 → SFPSETCC(NE0) (1 instruction, 1 cycle)
;
; Key optimization: GCC sometimes uses MAD+SETCC for x > 0 (negate then check
; sign) when two SETCCs are cheaper. LLVM should use the direct 2-SETCC form.
;
; Reference: ttsim-analysis/ERRATA.md GH-Q-005 (BH-specific, but WH analysis)
;            sfpi-gcc/gcc/testsuite/g++.target/tt/sfpi/gtzero-26919-wh.C

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpencc(i32, i32, i32)

; Test 1: x >= 0 (direct: single SFPSETCC with GTE0 mode)
; CHECK-LABEL: test_gte_zero:
; CHECK: sfpsetcc
; CHECK-NOT: sfpmad
; CHECK: sfppopc
define void @test_gte_zero() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppushc()
  ; mod1=4 is LREG_GTE0
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 4)
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: x < 0 (direct: single SFPSETCC with LT0 mode)
; CHECK-LABEL: test_lt_zero:
; CHECK: sfpsetcc
; CHECK-NOT: sfpmad
; CHECK: sfppopc
define void @test_lt_zero() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppushc()
  ; mod1=0 is LREG_LT0
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: x > 0 (requires 2 SETCCs: GTE0 + NE0, as per GCC gtzero test)
; This is the WH pattern for "greater than" — no single-instruction form.
; CHECK-LABEL: test_gt_zero:
; CHECK: sfpsetcc
; CHECK: sfpsetcc
; CHECK: sfppopc
define void @test_gt_zero() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppushc()
  ; GTE0 then NE0 = GT0
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 4)  ; GTE0
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 2)  ; NE0
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 4: v_if / v_else using SFPCOMPC
; CHECK-LABEL: test_if_else:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfpcompc
; CHECK: sfpmov
; CHECK: sfppopc
define void @test_if_else() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 0)
  ; if-branch: MAD
  %if_r = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  ; else-branch: MOV
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 8)  ; COMP mode
  %else_r = call i32 @llvm.riscv.tt.sfpmov(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %if_r, i32 0, i32 0, i32 0)
  ret void
}
