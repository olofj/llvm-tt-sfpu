; RUN: %llc %sfpu-bh-flags %s -o - | %FileCheck %s
;
; Realistic test: SFPU GELU kernel based on BH LLK ckernel_sfpu_gelu.h.
;
; GELU(x) = x * P(X <= x), where P is the Gaussian CDF.
; Tenstorrent implements two paths:
;
; === Approximate path (_calculate_gelu_appx_) ===
;   Uses a 6-piece piecewise-linear LUT (SFPLUTFP32) to approximate
;   the CDF, then multiplies by x:
;     half    = vConstFloatPrgm0         (0.5, loaded via SFPCONFIG)
;     half_in = in * half                (SFPMUL)
;     result  = lut2_sign(in, L0..L6)   (SFPLUTFP32 with SGN_UPDATE)
;     result  = half_in + result         (SFPADD / SFPMAD)
;   The lut2_sign variant uses SGN_UPDATE so the sign of the result tracks
;   the sign of the input — critical for GELU's odd-function-like behavior.
;
;   LUT coefficients (from _init_gelu_):
;     L0 = 0x37E7322B  (slopes:  0.4939/0.1928)
;     L4 = 0xB12286D8  (offsets: -0.1605/-0.0150)
;     L1 = 0x38E138F3  (slopes:  0.6099/0.6189)
;     L5 = 0xB437B479  (offsets: -0.2635/-0.2797)
;     L2 = 0x38003852  (slopes:  0.5000/0.5402)
;     L6 = 0x7C00AFA4  (offsets: 0.0/inf / -0.1194)
;
; === Accurate path (_calculate_gelu_accurate_) ===
;   Uses the CDF polynomial approximation from ckernel_sfpu_cdf.h:
;     For x >= 0: Horner evaluation of degree-4 polynomial (POLYVAL5)
;     For x < 0:  CDF(x) = 1 - CDF(-x), with sign handling
;   The Horner scheme produces 4 chained SFPMAD instructions.
;   Final result is CDF(x) * x (scaled=true).
;
; === Derivative path (_calculate_gelu_derivative_<true>) ===
;   Approximate: lut2() + conditional bias via v_if(val < 0) { val += 1 }
;   Uses SFPLUTFP32 + SFPSETCC + SFPADDI inside predication.
;
; This exercises:
; - SFPLOADI: LUT coefficient setup (12 loads for 6 LReg pairs)
; - SFPCONFIG: write 0.5 to programmable constant register
; - SFPLUTFP32: 6-piece LUT with SGN_UPDATE (lut2_sign) and SGN_RETAIN (lut2)
; - SFPMUL: half_in = in * 0.5
; - SFPMAD: Horner polynomial steps and multiply-accumulate
; - SFPADD: result = half_in + lut_result
; - SFPPUSHC/SFPSETCC/SFPPOPC: predication for sign handling
; - Scheduling: interleaving independent MADs across two rows
;
; Reference: tt-metal/tt_llk_blackhole/common/inc/sfpu/ckernel_sfpu_gelu.h

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfploadi(i32, i32)
declare i32 @llvm.riscv.tt.sfplutfp32(i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpadd(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpaddi(i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmov(i32, i32, i32)
declare void @llvm.riscv.tt.sfpconfig(i32, i32, i32)
declare void @llvm.riscv.tt.sfppushc()
declare void @llvm.riscv.tt.sfppopc()
declare void @llvm.riscv.tt.sfpcompc()
declare void @llvm.riscv.tt.sfpsetcc(i32, i32, i32)
declare void @llvm.riscv.tt.sfpnop()

; ---------------------------------------------------------------------------
; GELU init: load LUT coefficients + set vConstFloatPrgm0 = 0.5.
;
; _sfpu_load_imm32_(reg, val) -> two SFPLOADI (mod=10 for low, mod=8 for high).
; vConstFloatPrgm0 is set via SFPLOADI into L0, then SFPCONFIG to copy to
; the programmable constant register (register 11, config path).
;
; CHECK-LABEL: gelu_init:
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
; CHECK: sfploadi
; CHECK: sfploadi
; CHECK: sfpconfig
define void @gelu_init() {
entry:
  ; --- Load 0.5 into vConstFloatPrgm0 ---
  ; First load 0.5 (FP32 = 0x3F000000) into L0, then SFPCONFIG to const reg
  ; 0x3F000000: lower16 = 0x0000, upper16 = 0x3F00
  %half_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0x0000, i32 10)
  %half_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0x3F00, i32 8)
  call void @llvm.riscv.tt.sfpconfig(i32 0, i32 11, i32 0)

  ; --- Load 6-piece LUT coefficients ---
  ; L0 = 0x37E7322B: slopes for segments 5,6 (|x| in [0.5,1.0] and [0,0.5])
  %l0_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0x322B, i32 10)
  %l0_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0x37E7, i32 8)

  ; L4 = 0xB12286D8: offsets for segments 5,6
  %l4_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0x86D8, i32 10)
  %l4_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0xB122, i32 8)

  ; L1 = 0x38E138F3: slopes for segments 3,4 (|x| in [1.5,2.0] and [1.0,1.5])
  %l1_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0x38F3, i32 10)
  %l1_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0x38E1, i32 8)

  ; L5 = 0xB437B479: offsets for segments 3,4
  %l5_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0xB479, i32 10)
  %l5_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0xB437, i32 8)

  ret void
}

; ---------------------------------------------------------------------------
; GELU approximate: single Dst row.
;
; Sequence from _calculate_gelu_appx_ (one loop iteration):
;   in      = dst_reg[0]                         --> SFPLOAD
;   half    = vConstFloatPrgm0                    --> (already in CREG 11)
;   half_in = in * half                           --> SFPMUL(in, L11, L9, 0)
;   result  = lut2_sign(in, L0..L6)              --> SFPLUTFP32(7, mod=2)
;   result  = half_in + result                    --> SFPADD
;   dst_reg[0] = result                           --> SFPSTORE
;
; lut2_sign uses SGN_UPDATE (mod0 bit 2 = 0):
;   SFPLUTFP32_MOD0_FP16_6ENTRY_TABLE1 (2) | SGN_UPDATE (0) = 2
;
; CHECK-LABEL: gelu_appx_one_row:
; CHECK: sfpload
; CHECK: sfpmul
; CHECK: sfplutfp32
; CHECK: sfpadd
; CHECK: sfpstore
define void @gelu_appx_one_row() {
entry:
  ; Load input from Dst row 0
  %in = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; half_in = in * vConstFloatPrgm0 (CREG 11 = 0.5)
  ; SFPMUL(src_a=in, src_b=L11, src_c=L9(0.0), mod1=0)
  %half_in = call i32 @llvm.riscv.tt.sfpmul(i32 %in, i32 11, i32 9, i32 0)

  ; result = lut2_sign(in, L0, L1, L2, L4, L5, L6)
  ; SFPLUTFP32 with mod1 = FP16_6ENTRY_TABLE1(2) | SGN_UPDATE(0) = 2
  %lut_result = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 2)

  ; result = half_in + lut_result
  ; SFPADD(src_a=half_in, src_b=lut_result, src_c=L9(0.0), mod1=0)
  %result = call i32 @llvm.riscv.tt.sfpadd(i32 %half_in, i32 %lut_result, i32 9, i32 0)

  ; Store result back to Dst row 0
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)

  ret void
}

; ---------------------------------------------------------------------------
; GELU approximate: two rows — tests scheduling interleaving.
;
; Two independent rows should be interleaved by the scheduler to hide the
; 2-cycle SFPMUL latency. The ideal schedule is:
;   load0, load1, mul0, mul1, lut0, lut1, add0, add1, store0, store1
; No NOPs needed on BH due to hardware scoreboarding.
;
; CHECK-LABEL: gelu_appx_two_rows:
; CHECK: sfpload
; CHECK: sfpload
; CHECK: sfpmul
; CHECK-NOT: sfpnop
; CHECK: sfpmul
; CHECK: sfplutfp32
; CHECK: sfplutfp32
; CHECK: sfpadd
; CHECK: sfpadd
; CHECK: sfpstore
; CHECK: sfpstore
define void @gelu_appx_two_rows() {
entry:
  ; Load two rows
  %in0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %in1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)

  ; Multiply both by 0.5 (independent — scheduler can interleave)
  %half0 = call i32 @llvm.riscv.tt.sfpmul(i32 %in0, i32 11, i32 9, i32 0)
  %half1 = call i32 @llvm.riscv.tt.sfpmul(i32 %in1, i32 11, i32 9, i32 0)

  ; LUT evaluation for both rows
  %lut0 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 2)
  %lut1 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 2)

  ; Add half_in + lut_result for both rows
  %r0 = call i32 @llvm.riscv.tt.sfpadd(i32 %half0, i32 %lut0, i32 9, i32 0)
  %r1 = call i32 @llvm.riscv.tt.sfpadd(i32 %half1, i32 %lut1, i32 9, i32 0)

  ; Store both rows
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)

  ret void
}

; ---------------------------------------------------------------------------
; GELU accurate: CDF polynomial via Horner's method.
;
; From _calculate_cdf_appx_ and POLYVAL5 in ckernel_sfpu_polyval.h:
;   For |x| < 2.5:
;     CDF(x) = ((((c4*x + c3)*x + c2)*x + c1)*x + c0)
;     c4=0.0123, c3=-0.0528, c2=-0.0305, c1=0.4131, c0=0.4987
;   This generates 4 chained SFPMAD instructions (Horner scheme).
;
; The full CDF has a v_if(x < 0) / v_else for sign handling, plus
; a v_if(result > 1.0) clamp. The scaled variant multiplies by x at the end.
;
; CHECK-LABEL: gelu_accurate_horner:
; CHECK: sfpload
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfpmul
; CHECK: sfpstore
define void @gelu_accurate_horner() {
entry:
  ; Load input from Dst
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; Horner evaluation of degree-4 polynomial for CDF:
  ;   t1 = c4 * x + c3      (0.0123 * x - 0.0528)
  ;   t2 = t1 * x + c2      (t1 * x - 0.0305)
  ;   t3 = t2 * x + c1      (t2 * x + 0.4131)
  ;   cdf = t3 * x + c0     (t3 * x + 0.4987)
  ;
  ; In SFPU: SFPMAD(src_a, src_b, src_c, mod1)
  ; Coefficients are loaded into LRegs by init code.
  ; Using L8..L10 as coefficient CREGs for illustration.
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 8, i32 9, i32 0)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %t1, i32 %x, i32 10, i32 0)
  %t3 = call i32 @llvm.riscv.tt.sfpmad(i32 %t2, i32 %x, i32 8, i32 0)
  %cdf = call i32 @llvm.riscv.tt.sfpmad(i32 %t3, i32 %x, i32 10, i32 0)

  ; Scaled CDF: result = cdf * x (for GELU = x * CDF(x))
  ; SFPMUL(cdf, x, L9(0.0), 0)
  %result = call i32 @llvm.riscv.tt.sfpmul(i32 %cdf, i32 %x, i32 9, i32 0)

  ; Store
  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)

  ret void
}

; ---------------------------------------------------------------------------
; GELU accurate with sign handling: full CDF path.
;
; The real kernel handles negative inputs:
;   v_if (x < 0)
;     cdf = 1.0 - CDF(-x)
;   v_else
;     cdf = CDF(x)
;   v_endif
;   result = cdf * x   (scaled=true)
;
; This tests predication (pushc/setcc/compc/popc) around the Horner chain.
;
; CHECK-LABEL: gelu_accurate_signed:
; CHECK: sfpload
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfppopc
; CHECK: sfpcompc
; CHECK: sfppushc
; CHECK: sfpmad
; CHECK: sfpmad
; CHECK: sfppopc
; CHECK: sfpmul
; CHECK: sfpstore
define void @gelu_accurate_signed() {
entry:
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; v_if (x < 0) — negative path: CDF(x) = 1 - CDF(-x)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %x, i32 0, i32 0)  ; LT0 mode

  ; Horner for -x (simplified 2-step for test clarity)
  %neg_t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 8, i32 9, i32 0)
  %neg_cdf = call i32 @llvm.riscv.tt.sfpmad(i32 %neg_t1, i32 %x, i32 10, i32 0)

  ; v_else — positive path: CDF(x) = CDF(x) directly
  call void @llvm.riscv.tt.sfppopc()
  call void @llvm.riscv.tt.sfpcompc()
  call void @llvm.riscv.tt.sfppushc()

  %pos_t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 8, i32 9, i32 0)
  %pos_cdf = call i32 @llvm.riscv.tt.sfpmad(i32 %pos_t1, i32 %x, i32 10, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()

  ; Scale: result = cdf * x
  %result = call i32 @llvm.riscv.tt.sfpmul(i32 %pos_cdf, i32 %x, i32 9, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)

  ret void
}

; ---------------------------------------------------------------------------
; GELU derivative (approximate): LUT + conditional bias.
;
; From _calculate_gelu_derivative_<true, ITERATIONS>:
;   val = dst_reg[0]
;   val = lut2(val, L0..L6, lut_mode=1)    --> SFPLUTFP32, SGN_RETAIN
;   v_if (val < 0.0) { val = val + 1.0 }   --> pushc/setcc/addi/popc
;   dst_reg[0] = val
;
; lut_mode=1 -> SFPLUTFP32_MOD0_FP16_6ENTRY_TABLE1(2) | SGN_RETAIN(4) = 6
;
; The conditional +1.0 corrects the antisymmetric LUT output for the
; derivative's positive domain. The derivative coefficients model:
;   x <= 0.5 --> 0.8x + 0.5
;   x <= 1.0 --> 0.4x + 0.7
;   x <= 1.5 --> 0.1x + 0.99
;   x <= 2.0 --> -0.09x + 1.27
;   x <= 3.0 --> -0.075x + 1.235
;   x >  3.0 --> 1.0
;
; CHECK-LABEL: gelu_deriv_appx:
; CHECK: sfpload
; CHECK: sfplutfp32
; CHECK: sfppushc
; CHECK: sfpsetcc
; CHECK: sfpaddi
; CHECK: sfppopc
; CHECK: sfpstore
define void @gelu_deriv_appx() {
entry:
  ; Load input from Dst
  %val = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; LUT evaluation: lut2(val, L0..L6, lut_mode=1) -> SGN_RETAIN
  ; SFPLUTFP32(lreg_c=7, mod1=6)
  %lut_val = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 6)

  ; v_if (val < 0.0F)
  call void @llvm.riscv.tt.sfppushc()
  call void @llvm.riscv.tt.sfpsetcc(i32 %lut_val, i32 0, i32 0)  ; LT0

  ; val = val + 1.0  (1.0 in FP16 = 0x3C00)
  %biased = call i32 @llvm.riscv.tt.sfpaddi(i32 %lut_val, i32 0x3C00, i32 0)

  ; v_endif
  call void @llvm.riscv.tt.sfppopc()

  ; Store
  call void @llvm.riscv.tt.sfpstore(i32 %biased, i32 0, i32 0, i32 0)

  ret void
}

; ---------------------------------------------------------------------------
; GELU core (non-approximate): polynomial transform before LUT.
;
; From _calculate_gelu_core_<false>(in):
;   result = (in * in) * (in * 0.044715) + in
;   result *= 0.79788    (sqrt(2/pi))
;
; This is the pre-processing step that feeds into the tanh LUT for the
; standard GELU approximation: GELU(x) = 0.5*x*(1 + tanh(sqrt(2/pi)*(x + 0.044715*x^3)))
;
; The polynomial maps to:
;   t0 = in * 0.044715             --> SFPMUL (L8 holds 0.044715)
;   t1 = in * in                   --> SFPMUL
;   t2 = t1 * t0 + in             --> SFPMAD (x^2 * 0.044715*x + x)
;   result = t2 * 0.79788         --> SFPMUL (L10 holds sqrt(2/pi))
;
; The two SFPMUL(in*0.044715, in*in) are independent and should be
; interleaved by the scheduler.
;
; CHECK-LABEL: gelu_core_polynomial:
; CHECK: sfpload
; CHECK: sfpmul
; CHECK: sfpmul
; CHECK: sfpmad
; CHECK: sfpmul
; CHECK: sfpstore
define void @gelu_core_polynomial() {
entry:
  %in = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; t0 = in * 0.044715 (coefficient in L8)
  %t0 = call i32 @llvm.riscv.tt.sfpmul(i32 %in, i32 8, i32 9, i32 0)

  ; t1 = in * in (squaring — independent from t0)
  %t1 = call i32 @llvm.riscv.tt.sfpmul(i32 %in, i32 %in, i32 9, i32 0)

  ; t2 = t1 * t0 + in  =  x^2 * (x * 0.044715) + x  =  0.044715*x^3 + x
  ; SFPMAD(t1, t0, in, 0)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %t1, i32 %t0, i32 %in, i32 0)

  ; result = t2 * sqrt(2/pi)  =  t2 * 0.79788 (in L10)
  %result = call i32 @llvm.riscv.tt.sfpmul(i32 %t2, i32 10, i32 9, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)

  ret void
}

; ---------------------------------------------------------------------------
; GELU full approximate kernel: init + compute (2 rows unrolled).
;
; Models the complete _init_gelu_ + _calculate_gelu_appx_<2> sequence.
; Tests that the coefficient loading and compute are properly sequenced,
; and that two loop iterations can be interleaved.
;
; CHECK-LABEL: gelu_appx_full:
; CHECK: sfploadi
; CHECK: sfpconfig
; CHECK: sfploadi
; CHECK: sfpload
; CHECK: sfpmul
; CHECK: sfplutfp32
; CHECK: sfpadd
; CHECK: sfpstore
; CHECK: sfpload
; CHECK: sfpmul
; CHECK: sfplutfp32
; CHECK: sfpadd
; CHECK: sfpstore
define void @gelu_appx_full() {
entry:
  ; --- Init: set vConstFloatPrgm0 = 0.5 ---
  %half_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0x0000, i32 10)
  %half_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0x3F00, i32 8)
  call void @llvm.riscv.tt.sfpconfig(i32 0, i32 11, i32 0)

  ; --- Init: load L0 and L4 (first segment pair) ---
  %l0_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0x322B, i32 10)
  %l0_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0x37E7, i32 8)
  %l4_lo = call i32 @llvm.riscv.tt.sfploadi(i32 0x86D8, i32 10)
  %l4_hi = call i32 @llvm.riscv.tt.sfploadi(i32 0xB122, i32 8)

  ; --- Compute: row 0 ---
  %in0 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)
  %half0 = call i32 @llvm.riscv.tt.sfpmul(i32 %in0, i32 11, i32 9, i32 0)
  %lut0 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 2)
  %r0 = call i32 @llvm.riscv.tt.sfpadd(i32 %half0, i32 %lut0, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r0, i32 0, i32 0, i32 0)

  ; --- Compute: row 1 ---
  %in1 = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 16)
  %half1 = call i32 @llvm.riscv.tt.sfpmul(i32 %in1, i32 11, i32 9, i32 0)
  %lut1 = call i32 @llvm.riscv.tt.sfplutfp32(i32 7, i32 2)
  %r1 = call i32 @llvm.riscv.tt.sfpadd(i32 %half1, i32 %lut1, i32 9, i32 0)
  call void @llvm.riscv.tt.sfpstore(i32 %r1, i32 0, i32 0, i32 16)

  ret void
}
