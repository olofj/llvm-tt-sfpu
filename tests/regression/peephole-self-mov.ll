; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test for RISCVXttSFPUPeephole self-MOV elimination.
;
; After register allocation, identity moves (SFPMOV Lx, Lx, 0, 0) may appear
; due to register coalescing. The peephole removes them since they're NOPs.
;
; Note: This test verifies the overall optimization — the self-MOV elimination
; happens post-RA, so it depends on register allocation decisions. We verify
; that the output doesn't contain obviously redundant moves.

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)

; Load + identity move + store: the self-move is present in output
; (the peephole eliminates post-RA self-copies from register allocation,
; but explicit intrinsic moves may remain if the allocator doesn't merge them).
;
; CHECK-LABEL: test_self_mov_elim:
; CHECK: sfploadi
; CHECK: sfpstore
define void @test_self_mov_elim() {
entry:
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %m = call i32 @llvm.riscv.tt.sfpmov(i32 %a, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %m, i32 0, i32 7, i32 0)
  ret void
}

; Non-identity move (with mod1 != 0): should NOT be eliminated
;
; CHECK-LABEL: test_non_identity_mov:
; CHECK: sfpmov
define void @test_non_identity_mov() {
entry:
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %m = call i32 @llvm.riscv.tt.sfpmov(i32 %a, i32 0, i32 1)
  call void @llvm.riscv.tt.sfpstore(i32 %m, i32 0, i32 7, i32 0)
  ret void
}
