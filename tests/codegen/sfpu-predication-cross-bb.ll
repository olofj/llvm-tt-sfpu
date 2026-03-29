; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Test _lv variant selection when predicated regions (v_if/v_else/v_endif)
; span multiple basic blocks. The liveness pass must track CC stack depth
; globally across the CFG, not just within a single basic block.

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad.lv(i32, i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd.lv(i32, i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov.lv(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpcompc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)

; Test 1: Basic cross-block v_if.
; %x is defined in entry, SFPPUSHC is in entry, but SFPMAD is in if.body.
; The liveness pass must see that if.body is at CC depth 1 and %x was
; defined at depth 0, so SFPMAD needs _lv.
;
; CHECK-LABEL: test_cross_bb_vif:
; CHECK: sfpload
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad{{.*}}
; CHECK: sfppopc
; CHECK: sfpstore
define void @test_cross_bb_vif() {
entry:
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %x, i32 0, i32 0)
  br label %if.body

if.body:
  ; %x is live across predication: defined at depth 0, used here at depth 1.
  %x2 = call i32 @llvm.riscv.tt.sfpmad.lv(i32 %x, i32 %x, i32 %x, i32 9, i32 0)
  br label %if.end

if.end:
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %x2, i32 0, i32 0, i32 0)
  ret void
}

; Test 2: v_if/v_else across blocks.
; %val is live across both the if-body and else-body.
;
; CHECK-LABEL: test_cross_bb_if_else:
; CHECK: sfpload
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad{{.*}}
; CHECK: sfppopc
; CHECK: sfpcompc
; CHECK: sfppushc
; CHECK: sfpadd{{.*}}
; CHECK: sfppopc
; CHECK: sfpstore
define void @test_cross_bb_if_else() {
entry:
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %cond = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %cond, i32 0, i32 0)
  br label %if.body

if.body:
  %val.if = call i32 @llvm.riscv.tt.sfpmad.lv(i32 %val, i32 %val, i32 %cond, i32 9, i32 0)
  br label %v_else

v_else:
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpcompc()
  call void @llvm.riscv.tt.sfppushc()
  br label %else.body

else.body:
  ; %val.if is live across this predication boundary too.
  %val.else = call i32 @llvm.riscv.tt.sfpadd.lv(i32 %val.if, i32 10, i32 %val.if, i32 %cond, i32 0)
  br label %v_endif

v_endif:
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %val.else, i32 0, i32 0, i32 0)
  ret void
}

; Test 3: Value defined inside predicated region at same depth — NO _lv needed.
; %inner is defined at depth 1 and used at depth 1. Since DefCCDepth == UseCCDepth,
; no _lv variant is needed.
;
; CHECK-LABEL: test_same_depth_no_lv:
; CHECK: sfppushc
; CHECK: sfploadi
; CHECK: sfpmad{{.*l[0-7], l[0-7], l[0-7], l[0-7]}}
; CHECK-NOT: sfpmad_lv
; CHECK: sfppopc
define void @test_same_depth_no_lv() {
entry:
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 0, i32 0, i32 0)
  br label %inside

inside:
  ; Both definition and use are at depth 1 — no _lv needed.
  %a = call i32 @llvm.riscv.tt.sfploadi(i32 0, i32 16256)
  %b = call i32 @llvm.riscv.tt.sfpmad(i32 %a, i32 %a, i32 9, i32 0)
  br label %done

done:
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpstore(i32 %b, i32 0, i32 0, i32 0)
  ret void
}
