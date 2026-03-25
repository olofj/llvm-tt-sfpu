// sfpi.h — High-level SFPI API for LLVM XttSFPU backend
//
// Provides vFloat, vInt, vUInt wrapper types and v_if/v_else/v_endif
// control flow constructs, compatible with the sfpi-gcc SFPI library.
//
// This is the user-facing API. Internal intrinsics are in sfpi_internal.h.
//
// Reference: https://github.com/tenstorrent/sfpi
//            ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.2-3.3

#ifndef SFPI_H
#define SFPI_H

#include "sfpi_internal.h"

#ifdef __cplusplus

namespace sfpi {

// Force inline attribute for SFPI functions — SFPU vectors cannot be passed
// on the stack (E-009)
#define sfpi_inline __attribute__((always_inline)) inline

//===----------------------------------------------------------------------===//
// vFloat — 32-wide SFPU floating-point vector
//===----------------------------------------------------------------------===//

class vFloat {
  int reg_;  // LReg index (0-7 for allocatable)

public:
  sfpi_inline vFloat() : reg_(0) {}
  sfpi_inline explicit vFloat(int reg) : reg_(reg) {}

  // Load from immediate (SFPLOADI)
  sfpi_inline vFloat(float imm) {
    union { float f; unsigned u; } conv;
    conv.f = imm;
    // Load upper 16 bits as bfloat16 approximation
    reg_ = __builtin_riscv_tt_sfploadi(conv.u >> 16, SFPLOADI_MOD1_FLOATB);
  }

  sfpi_inline int reg() const { return reg_; }

  // Arithmetic operators using SFPU 3-operand instructions
  sfpi_inline vFloat operator*(const vFloat &rhs) const {
    int result = __builtin_riscv_tt_sfpmul(reg_, rhs.reg_, 9 /*L9=zero*/, 0);
    return vFloat(result);
  }

  sfpi_inline vFloat operator+(const vFloat &rhs) const {
    int result = __builtin_riscv_tt_sfpadd(10 /*L10=one*/, reg_, rhs.reg_, 0);
    return vFloat(result);
  }

  sfpi_inline vFloat operator-() const {
    // Negate by XOR with sign bit (SFPSETSGN with -1 constant)
    int result = __builtin_riscv_tt_sfpsetsgn(reg_, 0, 0);
    return vFloat(result);
  }

  // Multiply-accumulate: a * b + c
  sfpi_inline friend vFloat mad(const vFloat &a, const vFloat &b,
                                 const vFloat &c) {
    int result = __builtin_riscv_tt_sfpmad(a.reg_, b.reg_, c.reg_, 0);
    return vFloat(result);
  }

  // Absolute value
  sfpi_inline vFloat abs() const {
    int result = __builtin_riscv_tt_sfpabs(reg_, 0, 0);
    return vFloat(result);
  }

  // Assignment from register move
  sfpi_inline vFloat &operator=(const vFloat &rhs) {
    reg_ = __builtin_riscv_tt_sfpmov(rhs.reg_, 0, 0);
    return *this;
  }
};

//===----------------------------------------------------------------------===//
// vInt — 32-wide SFPU integer vector (sign-magnitude, C-028)
//===----------------------------------------------------------------------===//

class vInt {
  int reg_;

public:
  sfpi_inline vInt() : reg_(0) {}
  sfpi_inline explicit vInt(int reg) : reg_(reg) {}

  sfpi_inline int reg() const { return reg_; }

  // Integer add (SFPIADD)
  sfpi_inline vInt operator+(int imm) const {
    int result = __builtin_riscv_tt_sfpiadd(reg_, imm & 0xFFF, 0);
    return vInt(result);
  }

  // Integer subtract
  sfpi_inline vInt operator-(int imm) const {
    int result = __builtin_riscv_tt_sfpiadd(reg_, imm & 0xFFF,
                                             SFPXIADD_MOD1_IS_SUB);
    return vInt(result);
  }

  // Bitwise AND (SFPAND)
  sfpi_inline vInt operator&(const vInt &rhs) const {
    int result = __builtin_riscv_tt_sfpand(rhs.reg_, 0, 0);
    return vInt(result);
  }

  // Bitwise OR (SFPOR)
  sfpi_inline vInt operator|(const vInt &rhs) const {
    int result = __builtin_riscv_tt_sfpor(rhs.reg_, 0, 0);
    return vInt(result);
  }

  // Bitwise XOR (SFPXOR)
  sfpi_inline vInt operator^(const vInt &rhs) const {
    int result = __builtin_riscv_tt_sfpxor(rhs.reg_, 0, 0);
    return vInt(result);
  }

  // Bitwise NOT (SFPNOT)
  sfpi_inline vInt operator~() const {
    int result = __builtin_riscv_tt_sfpnot(reg_, 0, 0);
    return vInt(result);
  }

  // Shift (SFPSHFT)
  sfpi_inline vInt operator<<(int amount) const {
    int result = __builtin_riscv_tt_sfpshft(reg_, amount & 0xFFF, 0);
    return vInt(result);
  }
};

//===----------------------------------------------------------------------===//
// Dst load/store helpers
//===----------------------------------------------------------------------===//

// Load from Dst register to LReg
sfpi_inline vFloat dst_load(int addr_mode, int addr) {
  int result = __builtin_riscv_tt_sfpload(0, addr_mode, addr);
  return vFloat(result);
}

// Store LReg to Dst register
sfpi_inline void dst_store(const vFloat &val, int addr_mode, int addr) {
  __builtin_riscv_tt_sfpstore(val.reg(), 0, addr_mode, addr);
}

//===----------------------------------------------------------------------===//
// Predication: v_if / v_else / v_endif
//
// These implement SIMT-style divergent control flow using the SFPU's
// per-lane condition code flag stack.
//
// Usage:
//   v_if(condition) {
//     // code for lanes where condition is true
//   } v_else {
//     // code for lanes where condition is false
//   } v_endif;
//
// Reference: ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.3
//===----------------------------------------------------------------------===//

// RAII guard that pushes CC on construction and pops on destruction
class CCGuard {
public:
  sfpi_inline CCGuard() {
    __builtin_riscv_tt_sfppushc();
  }
  sfpi_inline ~CCGuard() {
    __builtin_riscv_tt_sfppopc();
  }
};

// v_if: push CC stack, set condition
// Implementation: create a CCGuard in scope, then SFPSETCC
#define v_if(cond_reg, cond_mod) \
  { \
    sfpi::CCGuard _cc_guard; \
    __builtin_riscv_tt_sfpsetcc((cond_reg), 0, (cond_mod));

// v_else: complement the condition (pop + complement + push)
#define v_else \
    __builtin_riscv_tt_sfppopc(); \
    __builtin_riscv_tt_sfpcompc(); \
    __builtin_riscv_tt_sfppushc();

// v_endif: close the scope (CCGuard destructor pops)
#define v_endif \
  }

//===----------------------------------------------------------------------===//
// Special function helpers
//===----------------------------------------------------------------------===//

// Approximate reciprocal (BH only)
sfpi_inline vFloat approx_recip(const vFloat &x) {
  int result = __builtin_riscv_tt_sfparecip(x.reg(), 0, 0);
  return vFloat(result);
}

// LUT-based FP32 function approximation (uses L0, L1, L7)
sfpi_inline vFloat lut_fp32(const vFloat &x, int mode) {
  int result = __builtin_riscv_tt_sfplutfp32(x.reg(), mode);
  return vFloat(result);
}

// Extract exponent
sfpi_inline vInt exponent(const vFloat &x) {
  int result = __builtin_riscv_tt_sfpexexp(x.reg(), 0, SFPEXEXP_MOD1_DEBIAS);
  return vInt(result);
}

// Extract mantissa
sfpi_inline vInt mantissa(const vFloat &x) {
  int result = __builtin_riscv_tt_sfpexman(x.reg(), 0, 0);
  return vInt(result);
}

// Leading zeros
sfpi_inline vInt leading_zeros(const vInt &x) {
  int result = __builtin_riscv_tt_sfplz(x.reg(), 0, 0);
  return vInt(result);
}

// Format cast
sfpi_inline vFloat cast_fp16a_to_fp32(const vFloat &x) {
  int result = __builtin_riscv_tt_sfpcast(x.reg(), 0, SFPCAST_MOD1_FP16A_TO_FP32);
  return vFloat(result);
}

sfpi_inline vFloat cast_fp16b_to_fp32(const vFloat &x) {
  int result = __builtin_riscv_tt_sfpcast(x.reg(), 0, SFPCAST_MOD1_FP16B_TO_FP32);
  return vFloat(result);
}

// NOP (for pipeline hazard avoidance)
sfpi_inline void nop() {
  __builtin_riscv_tt_sfpnop();
}

} // namespace sfpi

#endif // __cplusplus
#endif // SFPI_H
