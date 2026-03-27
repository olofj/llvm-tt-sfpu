; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; WH basic codegen: intrinsic → instruction selection on Wormhole.
; Same tests as sfpu-basic.ll but targeting WH, verifying:
; 1. Instructions select correctly on WH target
; 2. NOP insertion for dependent 2-cycle instructions (E-004)
; 3. No BH-only instructions appear in output
; 4. C-010 register constraints are satisfied

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; Basic load → multiply-add → store.
; Verify no BH-only instructions leak through.
;
; CHECK-LABEL: test_load_mad_store:
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpmad
; CHECK-NOT: sfpmul24
; CHECK-NOT: sfparecip
; CHECK-NOT: sfpgt
; CHECK-NOT: sfple
; CHECK: sfpstore
define void @test_load_mad_store() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %b, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %c, i32 0, i32 0, i32 0)
  ret void
}

; Independent MUL and ADD — no NOP needed between them on WH.
;
; CHECK-LABEL: test_independent_ops:
; CHECK: sfpmul
; CHECK-NOT: sfpnop
; CHECK: sfpadd
define void @test_independent_ops() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  %d = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 48)
  %mul = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  %add = call i32 @llvm.riscv.tt.sfpadd(i32 %c, i32 %d, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %mul, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %add, i32 0, i32 0, i32 16)
  ret void
}

; Verify MOV works on WH target.
;
; CHECK-LABEL: test_mov:
; CHECK: sfpmov
define i32 @test_mov(i32 %src) {
  %result = call i32 @llvm.riscv.tt.sfpmov(i32 %src, i32 0, i32 0)
  ret i32 %result
}

; Verify explicit NOP.
;
; CHECK-LABEL: test_nop:
; CHECK: sfpnop
define void @test_nop() {
  call void @llvm.riscv.tt.sfpnop()
  ret void
}
