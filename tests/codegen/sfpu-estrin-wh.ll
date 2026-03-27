; RUN: %llc %sfpu-wh-flags %s -o - | %FileCheck %s
;
; Estrin polynomial evaluation — the key optimization for WH.
;
; Horner's method is sequential: each MAD depends on the previous.
; Estrin's method splits into independent sub-chains that interleave.
;
; For degree-3: p(x) = a3*x^3 + a2*x^2 + a1*x + a0
;   Horner: t=a3*x+a2; t=t*x+a1; t=t*x+a0  (3 MADs, all dependent, 3 NOPs)
;   Estrin: lo=a1*x+a0; hi=a3*x+a2; x2=x*x; r=hi*x2+lo  (4 MADs, 2 independent pairs)
;
; WH cycle counts:
;   Horner degree-3: 3 MADs * (2+1 NOP) = 9 cycles
;   Estrin degree-3: 2 independent MADs (4 cycles) + MUL (3 cycles) + MAD (3 cycles) = 7 cycles
;   Savings: 22%
;
; For degree-5 (typical GELU):
;   Horner: 15 cycles (5 MADs * 3)
;   Estrin: ~10 cycles
;   Savings: 33%

target triple = "riscv32-unknown-unknown"

declare i32 @llvm.riscv.tt.sfpload(i32, i32, i32)
declare void @llvm.riscv.tt.sfpstore(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmad(i32, i32, i32, i32)
declare i32 @llvm.riscv.tt.sfpmul(i32, i32, i32, i32)

; ========================================================================
; Degree-3 Estrin: p(x) = a3*x^3 + a2*x^2 + a1*x + a0
; Split into: lo = a1*x + a0,  hi = a3*x + a2,  x2 = x*x
; Then: result = hi*x2 + lo
;
; The scheduler should interleave lo and hi (independent MADs):
;   sfpmad  (lo)     ← 2 cycles
;   sfpmad  (hi)     ← fills lo's delay slot!
;   sfpmul  (x2)     ← fills hi's delay slot!
;   sfpmad  (result) ← hi and x2 ready
;
; CHECK-LABEL: estrin_degree3:
; CHECK: sfpload
; CHECK: sfpmov
; CHECK: sfpmov
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
; CHECK: sfpmul
; CHECK: sfpmad
; CHECK: sfpstore
; ========================================================================
define void @estrin_degree3() {
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; Copy x into separate registers so Estrin sub-chains don't conflict.
  ; On WH, C-010 means dst=src_a, so each MAD writes to its src_a register.
  ; Without copies, all MADs using x would write to the same register.
  %x_for_lo = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %x_for_hi = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)

  ; lo = a1*x_copy1 + a0  (uses x_for_lo register)
  %lo = call i32 @llvm.riscv.tt.sfpmad(i32 %x_for_lo, i32 8, i32 9, i32 0)

  ; hi = a3*x_copy2 + a2  (uses x_for_hi register — INDEPENDENT of lo!)
  %hi = call i32 @llvm.riscv.tt.sfpmad(i32 %x_for_hi, i32 8, i32 10, i32 0)

  ; x2 = x * x  (uses original x)
  %x2 = call i32 @llvm.riscv.tt.sfpmul(i32 %x, i32 %x, i32 9, i32 0)

  ; result = hi * x2 + lo
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %hi, i32 %x2, i32 %lo, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; Degree-3 Horner (for comparison): same polynomial, sequential evaluation
; Every MAD depends on the previous → NOP after each.
;
; CHECK-LABEL: horner_degree3:
; CHECK: sfpmad
; CHECK-NEXT: sfpnop
; CHECK: sfpmad
; CHECK-NEXT: sfpnop
; CHECK: sfpmad
; ========================================================================
define void @horner_degree3() {
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; Horner: t = a3*x + a2
  %t0 = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 8, i32 10, i32 0)
  ; t = t*x + a1 (depends on t0!)
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 %t0, i32 9, i32 0)
  ; t = t*x + a0 (depends on t1!)
  %t2 = call i32 @llvm.riscv.tt.sfpmad(i32 %x, i32 %t1, i32 9, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %t2, i32 0, i32 0, i32 0)
  ret void
}

; ========================================================================
; Degree-5 Estrin: typical for GELU/SiLU activation functions
; p(x) = a5*x^5 + a4*x^4 + a3*x^3 + a2*x^2 + a1*x + a0
;
; Split into three independent pairs:
;   lo   = a1*x + a0
;   mid  = a3*x + a2
;   hi   = a5*x + a4
;   x2   = x*x
;   x4   = x2*x2
;   result = (hi*x2 + mid)*x2 + lo
;          = hi*x4 + mid*x2 + lo
;
; Three independent MADs (lo, mid, hi) can be scheduled in 4 cycles
; instead of Horner's 15 cycles!
;
; CHECK-LABEL: estrin_degree5:
; CHECK: sfpmov
; CHECK: sfpmov
; CHECK: sfpmov
; CHECK: sfpmad
; CHECK-NOT: sfpnop
; CHECK-NEXT: sfpmad
; CHECK-NOT: sfpnop
; CHECK: sfpmad
; ========================================================================
define void @estrin_degree5() {
  %x = call i32 @llvm.riscv.tt.sfpload(i32 0, i32 0, i32 0)

  ; Copy x for independent sub-chains (avoid C-010 WAW conflicts)
  %x_lo  = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %x_mid = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)
  %x_hi  = call i32 @llvm.riscv.tt.sfpmov(i32 %x, i32 0, i32 0)

  ; Three independent pairs (each in its own register)
  %lo  = call i32 @llvm.riscv.tt.sfpmad(i32 %x_lo, i32 8, i32 9, i32 0)
  %mid = call i32 @llvm.riscv.tt.sfpmad(i32 %x_mid, i32 8, i32 10, i32 0)
  %hi  = call i32 @llvm.riscv.tt.sfpmad(i32 %x_hi, i32 8, i32 9, i32 0)

  ; x^2 and x^4 (use original x)
  %x2 = call i32 @llvm.riscv.tt.sfpmul(i32 %x, i32 %x, i32 9, i32 0)
  %x4 = call i32 @llvm.riscv.tt.sfpmul(i32 %x2, i32 %x2, i32 9, i32 0)

  ; Combine: hi*x4 + mid, then *x2 + lo
  %t1 = call i32 @llvm.riscv.tt.sfpmad(i32 %hi, i32 %x4, i32 %mid, i32 0)
  %result = call i32 @llvm.riscv.tt.sfpmad(i32 %t1, i32 %x2, i32 %lo, i32 0)

  call void @llvm.riscv.tt.sfpstore(i32 %result, i32 0, i32 0, i32 0)
  ret void
}
