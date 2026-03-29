; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test for RISCVXttSFPUCluster pass: scalar instruction hoisting.
;
; The cluster pass hoists independent scalar ALU instructions above SFPU
; clusters to enable TTI fetch fusion (up to 4 SFPU instructions per
; wide fetch on the Baby RISC-V frontend).

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)

; Scalar computation (addi) should be hoisted above SFPU cluster.
; The SFPU instructions should appear consecutively.
;
; CHECK-LABEL: test_cluster_hoist:
; CHECK: sfploadi
; CHECK: sfpmad
; CHECK: sfpstore
define void @test_cluster_hoist(i32* %p, i32 %n) {
entry:
  %v0 = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %v1 = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16384)
  %r = call i32 @llvm.riscv.tt.sfpmad(i32 %v0, i32 %v1, i32 9, i32 0)
  %offset = add i32 %n, 16
  call void @llvm.riscv.tt.sfpstore(i32 %r, i32 0, i32 7, i32 0)
  store i32 %offset, i32* %p
  ret void
}
