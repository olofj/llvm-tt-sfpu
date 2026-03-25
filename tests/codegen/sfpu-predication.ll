; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test SFPU predication (v_if/v_else/v_endif) lowering.
; Verifies CC stack push/pop/complement sequences.

target triple = "riscv32-unknown-unknown"

declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpcompc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)

; Simple v_if pattern:
;   pushc → setcc → body → popc
; CHECK-LABEL: test_v_if:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmov
; CHECK: sfppopc
define void @test_v_if() {
  call void @llvm.riscv.tt.sfppushc()
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 0)
  %moved = call i32 @llvm.riscv.tt.sfpmov(i32 %val, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %moved, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  ret void
}

; v_if/v_else pattern:
;   pushc → setcc → if-body → popc → compc → pushc → else-body → popc
; CHECK-LABEL: test_v_if_else:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmov
; CHECK: sfppopc
; CHECK: sfpcompc
; CHECK: sfppushc
; CHECK: sfpmov
; CHECK: sfppopc
define void @test_v_if_else() {
  %cond = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; v_if
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %cond, i32 0, i32 0)
  %val_if = call i32 @llvm.riscv.tt.sfpmov(i32 %cond, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %val_if, i32 0, i32 0, i32 0)

  ; v_else
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpcompc()
  call void @llvm.riscv.tt.sfppushc()
  %val_else = call i32 @llvm.riscv.tt.sfpmov(i32 %cond, i32 0, i32 1)
  call void @llvm.riscv.tt.sfpstore(i32 %val_else, i32 0, i32 0, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()
  ret void
}
