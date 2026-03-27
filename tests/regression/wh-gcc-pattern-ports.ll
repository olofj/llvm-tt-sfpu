; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; Patterns ported from GCC WH test suite to verify LLVM produces equivalent
; (or better) output. Each test is annotated with the GCC source file.
;
; These tests are critical for catching regressions: if GCC correctly handles
; a WH-specific pattern but LLVM doesn't, we have a correctness bug.
;
; Source tests:
;   sfpi-gcc/gcc/testsuite/g++.target/tt/delay-34602-wh.C
;   sfpi-gcc/gcc/testsuite/g++.target/tt/shft2-26462-wh.C
;   sfpi-gcc/gcc/testsuite/g++.target/tt/swap-34602-wh.C
;   sfpi-gcc/gcc/testsuite/g++.target/tt/sfpi/muladd-14604-wh.C
;   sfpi-gcc/gcc/testsuite/g++.target/tt/sfpi/fpsub-14604-wh.C

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpabs(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpexexp(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpdivp2(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; ========================================================================
; Pattern from delay-34602-wh.C::dyn::one
; GCC output: SFPLOAD L0 → SFPMULI L0 → SFPNOP → SFPSTORE L0
; Key: SFPMULI is 2-cycle, SFPSTORE reads its result → NOP required
; ========================================================================

; CHECK-LABEL: gcc_delay_dyn_one:
; CHECK: sfpload
; CHECK: sfpmad
; CHECK: sfpnop
; CHECK: sfpstore
define void @gcc_delay_dyn_one() {
  %f = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %y = call i32 @llvm.riscv.tt.sfpmad(i32 %f, i32 8, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %y, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; Pattern from delay-34602-wh.C::dyn::two
; GCC output: SFPLOAD L0 → SFPMOV L1,L0 → SFPMULI L1 → SFPSTORE L0
; Key: Store uses original L0, not the MULI result, so NO NOP needed
; between MULI and STORE (they are independent!)
; ========================================================================

; CHECK-LABEL: gcc_delay_dyn_two:
; CHECK: sfpload
; CHECK: sfpmov
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpstore
define void @gcc_delay_dyn_two() {
  %f = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %copy = call i32 @llvm.riscv.tt.sfpmov(i32 %f, i32 0, i32 0)
  %y = call i32 @llvm.riscv.tt.sfpmad(i32 %copy, i32 8, i32 9, i32 0)
  ; Store the ORIGINAL value %f, not %y — independent of MAD result
  call void @llvm.riscv.tt.sfpstore(i32 %f, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; Pattern from sfpi/muladd-14604-wh.C
; Tests: a*b+c synthesis (MUL+ADD or MAD)
; GCC produces separate MUL+ADD with NOPs; LLVM should fuse to MAD
; ========================================================================

; CHECK-LABEL: gcc_muladd_fma:
; CHECK: sfpmad
; CHECK-NOT: sfpmul
; CHECK-NOT: sfpadd
; CHECK: sfpstore
define void @gcc_muladd_fma() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %c = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 32)
  ; a*b → tmp
  %tmp = call i32 @llvm.riscv.tt.sfpmul(i32 %a, i32 %b, i32 9, i32 0)
  ; tmp + c → result (should fuse with MUL into SFPMAD)
  %result = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %tmp, i32 %c, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; Pattern from sfpi/fpsub-14604-wh.C
; Tests: a - b synthesis on WH
; GCC on WH uses: MUL(b, L11(-1.0), L9) then ADD(L10, a, neg_b)
; LLVM should use negated-add or fuse differently
; ========================================================================

; CHECK-LABEL: gcc_fpsub:
; CHECK: sfpload
; CHECK: sfpload
; CHECK-NOT: sfpgt
; CHECK-NOT: sfple
; CHECK: sfpstore
define void @gcc_fpsub() {
  %a = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %b = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  ; Negate b: b * L11(-1.0)
  %neg_b = call i32 @llvm.riscv.tt.sfpmul(i32 %b, i32 11, i32 9, i32 0)
  ; a + (-b) = a - b
  %result = call i32 @llvm.riscv.tt.sfpadd(i32 10, i32 %a, i32 %neg_b, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; Pattern from pr13.C — NOP insertion across basic blocks
; Tests that NOP is inserted even when the dependent consumer is in a
; successor basic block (requires CFG-aware analysis)
; ========================================================================

; CHECK-LABEL: gcc_cross_bb_nop:
; CHECK: sfpmad
; CHECK: sfpnop
; CHECK: sfpstore
define void @gcc_cross_bb_nop(i1 %cond) {
entry:
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  br i1 %cond, label %then, label %else

then:
  ; Consumer in a different basic block — still needs NOP
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void

else:
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 16)
  ret void
}

; ========================================================================
; Multi-step pipeline: load → exexp → predicate → Horner → store
; Full realistic WH kernel exercising scheduling + predication + NOPs
; ========================================================================

; CHECK-LABEL: gcc_full_pipeline:
; CHECK: sfpload
; CHECK: sfpexexp
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfppopc
; CHECK: sfpstore
define void @gcc_full_pipeline() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %exp = call i32 @llvm.riscv.tt.sfpexexp(i32 %val, i32 0, i32 2)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %exp, i32 0, i32 4)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 8, i32 9, i32 0)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %val, i32 %t1, i32 10, i32 0)
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %t2, i32 0, i32 0, i32 0)
  ret void
}
