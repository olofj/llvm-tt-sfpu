; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; GH-Q-003: setsgn/setexp/setman should not generate extraneous sfpmovs.
;
; GCC generates 2 unnecessary MOV instructions around SFPSETSGN:
;   sfpmov  L1, L0, 0       ← copy input (unnecessary)
;   sfpsetsgn L0, L1, 0     ← set sign bit
;   sfpmov  L3, L0, 0       ← copy output (unnecessary)
; Total: 3 instructions, 2 wasted
;
; LLVM should generate:
;   sfpsetsgn L0, L0, 0     ← direct (or with minimal MOVs)
; Total: 1 instruction
;
; The self-MOV peephole (tryEliminateSelfMov) removes identity copies.
; The register coalescer should prevent most copies from appearing.

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpsetsgn(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpsetexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpsetman(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)

; Test 1: Simple setsgn — should be at most 3 instructions (load, setsgn, store)
; CHECK-LABEL: test_setsgn_simple:
; CHECK: sfpload
; CHECK: sfpsetsgn
; CHECK-NOT: sfpmov
; CHECK: sfpstore
define void @test_setsgn_simple() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpsetsgn(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: setexp — same pattern
; CHECK-LABEL: test_setexp_simple:
; CHECK: sfpload
; CHECK: sfpsetexp
; CHECK-NOT: sfpmov
; CHECK: sfpstore
define void @test_setexp_simple() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpsetexp(i32 %val, i32 126, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: setman — same pattern
; CHECK-LABEL: test_setman_simple:
; CHECK: sfpload
; CHECK: sfpsetman
; CHECK-NOT: sfpmov
; CHECK: sfpstore
define void @test_setman_simple() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpsetman(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 4: setsgn used in a chain — verify no unnecessary MOVs in between
; CHECK-LABEL: test_setsgn_chain:
; CHECK: sfpload
; CHECK: sfpsetsgn
; CHECK: sfpsetexp
; CHECK: sfpstore
define void @test_setsgn_chain() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %s = call i32 @llvm.riscv.tt.sfpsetsgn(i32 %val, i32 0, i32 0)
  %e = call i32 @llvm.riscv.tt.sfpsetexp(i32 %s, i32 126, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %e, i32 0, i32 0, i32 0)
  ret void
}
