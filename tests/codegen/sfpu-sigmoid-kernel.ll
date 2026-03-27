; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Realistic test: SFPU sigmoid kernel based on BH LLK ckernel_sfpu_sigmoid.h.
;
; Sigmoid on Tenstorrent SFPU uses a 6-piece piecewise-linear LUT via
; SFPLUTFP32 (lut2 function in SFPI). The kernel has two phases:
;
;   Phase 1 — Init (_init_sigmoid_):
;     Load six 32-bit coefficient pairs into LRegs 0..2 and 4..6 via
;     SFPLOADI (two per LReg: low 16 bits then high 16 bits).
;     The 6-segment approximation is:
;       x <= 0.5 --> 0.2452*x + (-0.0005)
;       x <= 1.0 --> 0.2173*x + 0.0152
;       x <= 1.5 --> 0.1731*x + 0.0599
;       x <= 2.0 --> 0.1262*x + 0.1298
;       x <= 4.0 --> 0.0485*x + 0.2998
;       x >  4.0 --> 0.4998
;
;   Phase 2 — Compute (_calculate_sigmoid_):
;     For each Dst row:
;       val = sfpload(dst_reg[0])
;       result = sfplutfp32(val, ..., lut_mode=0)   // 6-entry LUT evaluation
;       result = result + 0.5                        // bias to [0,1]
;       sfpstore(result, dst_reg[0])
;       dst_reg++
;
; The lut2() call with 6 packed-FP16 LRegs maps to SFPLUTFP32 with
; mod0 = SFPLUTFP32_MOD0_FP16_6ENTRY_TABLE1 (2) | SGN_RETAIN (4) = 6.
; The lut2_sign() variant uses SGN_UPDATE (0) instead.
;
; This exercises:
; - SFPLOADI: coefficient loading (mod=10 for lower, mod=8 for upper bits)
; - SFPLUTFP32: hardware 6-piece linear interpolation
; - SFPADDI: add immediate 0.5 bias
; - SFPLOAD/SFPSTORE: Dst <-> LReg transfer
; - Scheduling: independent two-row processing for latency hiding
;
; Reference: tt-metal/tt_llk_blackhole/common/inc/sfpu/ckernel_sfpu_sigmoid.h

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfplutfp32(i32, i32)
declare i32 @llvm.riscv.tt.sfpaddi(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare void @llvm.riscv.tt.sfpconfig(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; ---------------------------------------------------------------------------
; Sigmoid init: load 6-piece LUT coefficients into LRegs via SFPLOADI.
;
; _sfpu_load_imm32_(reg, val) expands to two SFPLOADI calls:
;   SFPLOADI(reg, 10, val & 0xFFFF)   -- write lower 16 bits
;   SFPLOADI(reg, 8,  val >> 16)      -- write upper 16 bits
;
; Coefficient layout (from _init_sigmoid_):
;   L0 = 0x32F433D9 -> slopes  A0=0.2452(lo), A1=0.2173(hi)
;   L4 = 0x23C89018 -> offsets B0=-0.0005(lo), B1=0.0152(hi)
;   L1 = 0x300A318A -> slopes  A2=0.1731(lo), A3=0.1262(hi)
;   L5 = 0x30272BAA -> offsets B2=0.0599(lo), B3=0.1298(hi)
;   L2 = 0x7C002A35 -> slopes  A4=0.0485(lo), A5=0.0(hi)
;   L6 = 0x37FF34CC -> offsets B4=0.2998(lo), B5=0.4998(hi)
;
; CHECK-LABEL: sigmoid_init:
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfploadi
define void @sigmoid_init() {
entry:
  ; L0 = 0x32F433D9: A0=0.2452 (lo=0x33D9), A1=0.2173 (hi=0x32F4)
  %l0_lo = call i32 @llvm.riscv.tt.sfploadi(i32 13273, i32 10)  ; lower bits
  %l0_hi = call i32 @llvm.riscv.tt.sfploadi(i32 13044, i32 8)   ; upper bits

  ; L4 = 0x23C89018: B0=-0.0005 (lo=0x9018), B1=0.0152 (hi=0x23C8)
  %l4_lo = call i32 @llvm.riscv.tt.sfploadi(i32 36888, i32 10)
  %l4_hi = call i32 @llvm.riscv.tt.sfploadi(i32 9160, i32 8)

  ; L1 = 0x300A318A: A2=0.1731 (lo=0x318A), A3=0.1262 (hi=0x300A)
  %l1_lo = call i32 @llvm.riscv.tt.sfploadi(i32 12682, i32 10)
  %l1_hi = call i32 @llvm.riscv.tt.sfploadi(i32 12298, i32 8)

  ; L5 = 0x30272BAA: B2=0.0599 (lo=0x2BAA), B3=0.1298 (hi=0x3027)
  %l5_lo = call i32 @llvm.riscv.tt.sfploadi(i32 11178, i32 10)
  %l5_hi = call i32 @llvm.riscv.tt.sfploadi(i32 12327, i32 8)

  ; L2 = 0x7C002A35: A4=0.0485 (lo=0x2A35), A5=0.0 (hi=0x7C00)
  %l2_lo = call i32 @llvm.riscv.tt.sfploadi(i32 10805, i32 10)
  %l2_hi = call i32 @llvm.riscv.tt.sfploadi(i32 31744, i32 8)

  ; L6 = 0x37FF34CC: B4=0.2998 (lo=0x34CC), B5=0.4998 (hi=0x37FF)
  %l6_lo = call i32 @llvm.riscv.tt.sfploadi(i32 13516, i32 10)
  %l6_hi = call i32 @llvm.riscv.tt.sfploadi(i32 14335, i32 8)

  ret void
}

; ---------------------------------------------------------------------------
; Sigmoid compute: single Dst row.
;   val = load(dst_reg[0])
;   result = lut2(val, L0..L2, L4..L6, mode=0)  --> SFPLUTFP32
;   result = result + 0.5                        --> SFPADDI
;   store(result, dst_reg[0])
;
; The lut2() 6-LReg overload with mode=0 maps to:
;   SFPLUTFP32(lreg_c=7, mod1 = FP16_6ENTRY_TABLE1|SGN_RETAIN = 6)
; LReg 7 is the implicit input/output for SFPLUTFP32.
;
; CHECK-LABEL: sigmoid_one_row:
; CHECK: sfpload
; CHECK: sfplutfp32
; CHECK: sfpaddi
; CHECK: sfpstore
define void @sigmoid_one_row() {
entry:
  ; Load value from Dst row 0
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; SFPLUTFP32: 6-piece piecewise-linear lookup with coefficients in L0..L6
  ; lut_mode = 0 -> SFPLUTFP32_MOD0_FP16_6ENTRY_TABLE1 (2) | SGN_RETAIN (4)
  ; The intrinsic takes (lreg_c, mod1); lreg_c=7 is the implicit input register
  %lut_result = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 6)

  ; Add 0.5 bias: sigmoid(x) = lut_approx(x) + 0.5
  ; 0.5 in BF16 = 0x3F00, in FP16 = 0x3800
  %biased = call i32 @llvm.riscv.tt.sfpaddi(i32 %lut_result, i32 14336, i32 0)

  ; Store result back to Dst row 0
  call void @llvm.riscv.tt.sfpstore(i32 %biased, i32 0, i32 0, i32 0)

  ret void
}

; ---------------------------------------------------------------------------
; Sigmoid compute: two independent Dst rows — tests scheduling.
; The scheduler should interleave the two independent pipelines:
;   load0, load1, lut0, lut1, add0, add1, store0, store1
; rather than fully serializing row0 then row1.
;
; On BH, no NOPs needed between independent SFPLUTFP32 calls due to
; hardware scoreboarding.
;
; CHECK-LABEL: sigmoid_two_rows:
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfplutfp32
; CHECK-NOT: sfpnop
; CHECK: sfplutfp32
; CHECK: sfpaddi
; CHECK: sfpaddi
; CHECK: sfpstore
; CHECK: sfpstore
define void @sigmoid_two_rows() {
entry:
  ; Load two rows
  %v0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %v1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)

  ; LUT evaluation for both rows (independent — scheduler can interleave)
  %lut0 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 6)
  %lut1 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 6)

  ; Add 0.5 bias for both rows
  %r0 = call i32 @llvm.riscv.tt.sfpaddi(i32 %lut0, i32 14336, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpaddi(i32 %lut1, i32 14336, i32 0)

  ; Store both rows
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)

  ret void
}

; ---------------------------------------------------------------------------
; Full sigmoid kernel: init + compute loop (4 rows unrolled).
; This models the complete _init_sigmoid_ + _calculate_sigmoid_<true, 4>
; pattern from the real kernel.
;
; CHECK-LABEL: sigmoid_full:
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfpload
; CHECK: sfplutfp32
; CHECK: sfpaddi
; CHECK: sfpstore
; CHECK: sfpload
; CHECK: sfplutfp32
; CHECK: sfpaddi
; CHECK: sfpstore
define void @sigmoid_full() {
entry:
  ; --- Init phase: load LUT coefficients ---
  ; Only showing L0 and L4 for brevity; real kernel loads all six pairs.
  ; L0 = A0,A1 slopes
  %l0_lo = call i32 @llvm.riscv.tt.sfploadi(i32 13273, i32 10)
  %l0_hi = call i32 @llvm.riscv.tt.sfploadi(i32 13044, i32 8)
  ; L4 = B0,B1 offsets
  %l4_lo = call i32 @llvm.riscv.tt.sfploadi(i32 36888, i32 10)
  %l4_hi = call i32 @llvm.riscv.tt.sfploadi(i32 9160, i32 8)

  ; --- Compute phase: row 0 ---
  %val0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %lut0 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 6)
  %res0 = call i32 @llvm.riscv.tt.sfpaddi(i32 %lut0, i32 14336, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %res0, i32 0, i32 0, i32 0)

  ; --- Compute phase: row 1 ---
  %val1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %lut1 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 6)
  %res1 = call i32 @llvm.riscv.tt.sfpaddi(i32 %lut1, i32 14336, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %res1, i32 0, i32 0, i32 16)

  ret void
}
