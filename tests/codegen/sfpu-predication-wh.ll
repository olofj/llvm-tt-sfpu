; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH predication test — CC stack operations for SIMT-style divergent control.
; Tests v_if / v_else / v_endif patterns on Wormhole.
;
; The CC stack (SFPPUSHC/SFPPOPC/SFPCOMPC) is identical between WH and BH,
; but this test verifies they work correctly on WH target.
;
; Reference: ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.3 (Lane Predication)

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpcompc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpencc(i32, i32, i32)

; Test 1: Simple v_if / v_endif
;
; CHECK-LABEL: test_wh_v_if:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfppopc
define void @test_wh_v_if() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: v_if / v_else / v_endif (uses SFPCOMPC to invert predicate)
;
; CHECK-LABEL: test_wh_v_if_else:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfpcompc
; CHECK: sfpmov
; CHECK: sfppopc
define void @test_wh_v_if_else() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 0)
  ; if-branch
  %if_result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  ; else-branch
  call void @llvm.riscv.tt.sfpcompc()
  %else_result = call i32 @llvm.riscv.tt.sfpmov(i32 %val, i32 0, i32 0)
  ; endif
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %if_result, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: Nested predication (v_if inside v_if)
;
; CHECK-LABEL: test_wh_nested_predication:
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfppopc
; CHECK: sfppopc
define void @test_wh_nested_predication() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %val2 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  ; Outer v_if
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %val, i32 0, i32 0)
  ; Inner v_if
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %val2, i32 0, i32 4)
  ; Body (only lanes where both conditions are true)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %val2, i32 9, i32 0)
  ; Inner v_endif
  call void @llvm.riscv.tt.sfppopc()
  ; Outer v_endif
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
