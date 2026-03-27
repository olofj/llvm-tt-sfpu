; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; Predication elision tests: when a v_if body is a single safe instruction,
; the PUSHC/SETCC/POPC overhead (3 instructions) may exceed the body cost.
;
; Case 1: Large v_if body (keep predication — too many instructions to speculate)
; Case 2: Tiny v_if body (candidate for elision — body < predication overhead)
;
; Note: actual elision requires a dedicated pass. These tests document the
; expected patterns and verify the overhead.

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)

; Test 1: Large predicated body — predication justified.
; 3 instructions in body > 3 instructions of predication overhead.
;
; CHECK-LABEL: large_predicated_body:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfppopc
define void @large_predicated_body() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %cond = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %cond, i32 0, i32 4)
  ; Large body (3 MADs)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %t1, i32 10, i32 0)
  %t3 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %t2, i32 10, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %t3, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: Tiny predicated body — candidate for elision.
; 1 instruction in body vs 3 instructions of overhead.
; Total with predication: 4 instructions.
; Total without (speculative): 1 instruction.
;
; Current output (no elision pass):
; CHECK-LABEL: tiny_predicated_body:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmov
; CHECK: sfppopc
define void @tiny_predicated_body() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %cond = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %cond, i32 0, i32 4)
  ; Tiny body: single MOV — overhead of predication exceeds body
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
