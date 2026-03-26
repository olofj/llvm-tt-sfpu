; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Regression test for SFPLZ + SFPSETCC → SFPLZ with CC mode peephole.
; GCC fuses these in rvtt-peephole.md. LLVM does it in RISCVXttSFPUPeephole.
;
; Pattern:
;   sfplz  l0, l1, 0, 0    ; leading zeros, mod1=0 (no CC)
;   sfpsetcc l0, l1, 0, 2  ; set CC: result != 0 (NE0 mode)
; Fuses to:
;   sfplz  l0, l1, 0, 2    ; leading zeros with CC set (mod1=CC_NE0)
;
; Reference: sfpi-gcc/gcc/config/riscv/tt/rvtt-peephole.md lines 22-42

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfplz(i32, i32, i32)
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)

; After peephole fusion, SFPLZ should have CC mode set directly.
; The separate SFPSETCC should be eliminated.
;
; CHECK-LABEL: test_lz_setcc_fusion:
; CHECK: sfpload
; CHECK: sfplz
; CHECK: sfppushc
; CHECK-NOT: sfpsetcc
; CHECK: sfpmov
; CHECK: sfppopc
; CHECK: sfpstore
define void @test_lz_setcc_fusion() {
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; Leading zeros count with subsequent CC check
  %lz = call i32 @llvm.riscv.tt.sfplz(i32 %val, i32 0, i32 0)

  ; v_if (lz != 0) — should fuse with the LZ above
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %lz, i32 0, i32 2)  ; NE0 mode

  ; Body: just a MOV
  %moved = call i32 @llvm.riscv.tt.sfpmov(i32 %lz, i32 0, i32 0)

  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %moved, i32 0, i32 0, i32 0)
  ret void
}
