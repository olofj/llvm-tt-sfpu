/*
 * sfpi_compat.h — SFPI builtin compatibility layer for GCC ↔ LLVM
 *
 * tt-metal's SFPI headers use __builtin_rvtt_* (GCC-specific names).
 * This header provides the mapping to __builtin_riscv_tt_* (LLVM names)
 * when compiling with clang.
 *
 * Usage: Include this BEFORE sfpi.h in the include path.
 * The tt-metal build system should add -include sfpi_compat.h or
 * place this file so it's picked up by sfpi_builtins.h.
 *
 * This file handles the three main differences:
 * 1. Builtin name prefix: __builtin_rvtt_* → __builtin_riscv_tt_*
 * 2. instrn_buffer argument: GCC passes it explicitly, LLVM doesn't need it
 * 3. WH/BH dispatch: GCC uses __riscv_xtttensixwh/bh, LLVM uses __xttsfpu_wh/bh
 */

#ifndef SFPI_COMPAT_H
#define SFPI_COMPAT_H

#ifdef __clang__

/* ---- Architecture detection ---- */
/* GCC: __riscv_xtttensixwh, __riscv_xtttensixbh
 * LLVM: TBD — for now use target attribute check */
#if defined(__xttsfpu_bh) || defined(__SFPU_BH__)
#define __riscv_xtttensixbh 1
#elif defined(__xttsfpu_wh) || defined(__SFPU_WH__)
#define __riscv_xtttensixwh 1
#endif

/* ---- Core instruction builtins ---- */
/* These map the GCC builtin names to LLVM intrinsic-backed builtins.
 * The key difference: GCC builtins take an instrn_buffer pointer as first arg;
 * LLVM intrinsics don't need it (the instruction is emitted directly). */

/* NOP */
#define __builtin_rvtt_sfpnop() __builtin_riscv_tt_sfpnop()

/* CC stack */
#define __builtin_rvtt_sfppushc(mod) __builtin_riscv_tt_sfppushc()
#define __builtin_rvtt_sfppopc(mod) __builtin_riscv_tt_sfppopc()
#define __builtin_rvtt_sfpcompc() __builtin_riscv_tt_sfpcompc()
#define __builtin_rvtt_sfpencc(imm, mod) __builtin_riscv_tt_sfpencc(imm, mod)

/* Condition codes */
#define __builtin_rvtt_sfpsetcc_i(imm, mod) __builtin_riscv_tt_sfpsetcc(0, imm, mod)
#define __builtin_rvtt_sfpsetcc_v(src, mod) __builtin_riscv_tt_sfpsetcc(src, 0, mod)

/* Register operations */
#define __builtin_rvtt_sfpmov(src, mod) __builtin_riscv_tt_sfpmov(src, 0, mod)
#define __builtin_rvtt_sfpmov_lv(live, src, mod) __builtin_riscv_tt_sfpmov_lv(live, src, 0, mod)
#define __builtin_rvtt_sfpabs(src, mod) __builtin_riscv_tt_sfpabs(src, 0, mod)
#define __builtin_rvtt_sfpabs_lv(live, src, mod) __builtin_riscv_tt_sfpabs_lv(live, src, 0, mod)
#define __builtin_rvtt_sfpnot(src) __builtin_riscv_tt_sfpnot(src, 0, 0)
#define __builtin_rvtt_sfpnot_lv(live, src) __builtin_riscv_tt_sfpnot_lv(live, src, 0, 0)

/* Exponent/mantissa operations */
#define __builtin_rvtt_sfpexexp(src, mod) __builtin_riscv_tt_sfpexexp(src, 0, mod)
#define __builtin_rvtt_sfpexexp_lv(live, src, mod) __builtin_riscv_tt_sfpexexp_lv(live, src, 0, mod)
#define __builtin_rvtt_sfpexman(src, mod) __builtin_riscv_tt_sfpexman(src, 0, mod)
#define __builtin_rvtt_sfpexman_lv(live, src, mod) __builtin_riscv_tt_sfpexman_lv(live, src, 0, mod)
#define __builtin_rvtt_sfplz(src, mod) __builtin_riscv_tt_sfplz(src, 0, mod)
#define __builtin_rvtt_sfplz_lv(live, src, mod) __builtin_riscv_tt_sfplz_lv(live, src, 0, mod)

/* Logic operations */
#define __builtin_rvtt_sfpand(dst, src) __builtin_riscv_tt_sfpand(src, 0, 0)
#define __builtin_rvtt_sfpor(dst, src) __builtin_riscv_tt_sfpor(src, 0, 0)
#define __builtin_rvtt_sfpxor(dst, src) __builtin_riscv_tt_sfpxor(src, 0, 0)

/* Cast / rounding */
#define __builtin_rvtt_sfpcast(src, mod) __builtin_riscv_tt_sfpcast(src, 0, mod)
#define __builtin_rvtt_sfpcast_lv(live, src, mod) __builtin_riscv_tt_sfpcast_lv(live, src, 0, mod)

/* Config */
#define __builtin_rvtt_sfpconfig_v(src, mod) __builtin_riscv_tt_sfpconfig(0, src, mod)

/* ---- Architecture-dispatched builtins (BH) ---- */
#ifdef __riscv_xtttensixbh

/* Load/Store BH */
#define __builtin_rvtt_bh_sfpload(buf, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpload(mod0, mode, addr)
#define __builtin_rvtt_bh_sfpload_lv(buf, live, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpload_lv(live, mod0, mode, addr)
#define __builtin_rvtt_bh_sfpstore(buf, src, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpstore(src, mod0, mode, addr)
#define __builtin_rvtt_bh_sfpxloadi(buf, mod0, imm16, x1, x2) \
    __builtin_riscv_tt_sfploadi(mod0, imm16)
#define __builtin_rvtt_bh_sfpxloadi_lv(buf, live, mod0, imm16, x1, x2) \
    __builtin_riscv_tt_sfploadi(mod0, imm16)

/* 3-operand arithmetic BH */
#define __builtin_rvtt_bh_sfpmad(a, b, c, mod) __builtin_riscv_tt_sfpmad(a, b, c, mod)
#define __builtin_rvtt_bh_sfpmad_lv(live, a, b, c, mod) __builtin_riscv_tt_sfpmad_lv(live, a, b, c, mod)
#define __builtin_rvtt_bh_sfpmul(a, b, mod) __builtin_riscv_tt_sfpmul(a, b, 9, mod)
#define __builtin_rvtt_bh_sfpmul_lv(live, a, b, mod) __builtin_riscv_tt_sfpmul_lv(live, a, b, 9, mod)
#define __builtin_rvtt_bh_sfpadd(a, b, mod) __builtin_riscv_tt_sfpadd(10, a, b, mod)
#define __builtin_rvtt_bh_sfpadd_lv(live, a, b, mod) __builtin_riscv_tt_sfpadd_lv(live, 10, a, b, mod)

/* Immediate arithmetic BH */
#define __builtin_rvtt_bh_sfpmuli(buf, src, imm16, x1, x2, mod) \
    __builtin_riscv_tt_sfpmuli(src, imm16, mod)
#define __builtin_rvtt_bh_sfpaddi(buf, src, imm16, x1, x2, mod) \
    __builtin_riscv_tt_sfpaddi(src, imm16, mod)

/* Unary with immediate BH */
#define __builtin_rvtt_bh_sfpsetexp_i(buf, imm12, x1, x2, src) \
    __builtin_riscv_tt_sfpsetexp(src, imm12, 0)
#define __builtin_rvtt_bh_sfpsetexp_v(dst, src) \
    __builtin_riscv_tt_sfpsetexp(src, 0, 0)
#define __builtin_rvtt_bh_sfpsetman_i(buf, imm12, x1, x2, src, mod) \
    __builtin_riscv_tt_sfpsetman(src, imm12, mod)
#define __builtin_rvtt_bh_sfpsetman_v(dst, src) \
    __builtin_riscv_tt_sfpsetman(src, 0, 0)
#define __builtin_rvtt_bh_sfpsetsgn_i(buf, imm12, x1, x2, src) \
    __builtin_riscv_tt_sfpsetsgn(src, imm12, 0)
#define __builtin_rvtt_bh_sfpsetsgn_v(dst, src) \
    __builtin_riscv_tt_sfpsetsgn(src, 0, 0)
#define __builtin_rvtt_bh_sfpdivp2(buf, imm12, x1, x2, src, mod) \
    __builtin_riscv_tt_sfpdivp2(src, imm12, mod)
#define __builtin_rvtt_bh_sfpdivp2_lv(buf, live, imm12, x1, x2, src, mod) \
    __builtin_riscv_tt_sfpdivp2_lv(live, src, imm12, mod)

/* Integer operations BH */
#define __builtin_rvtt_bh_sfpxiadd_i(buf, src, imm12, x1, x2, mod) \
    __builtin_riscv_tt_sfpiadd(src, imm12, mod)
#define __builtin_rvtt_bh_sfpxiadd_i_lv(buf, live, src, imm12, x1, x2, mod) \
    __builtin_riscv_tt_sfpiadd(src, imm12, mod)
#define __builtin_rvtt_bh_sfpxiadd_v(dst, src, mod) \
    __builtin_riscv_tt_sfpiadd(src, 0, mod)

/* Shift BH */
#define __builtin_rvtt_bh_sfpshft_i(buf, dst, imm12, x1, x2, mod) \
    __builtin_riscv_tt_sfpshft(dst, imm12, mod)
#define __builtin_rvtt_bh_sfpshft_v(dst, src, mod) \
    __builtin_riscv_tt_sfpshft(src, 0, mod)

/* Comparison BH */
#define __builtin_rvtt_bh_sfpxfcmps(buf, v, f, x1, x2, mod) \
    __builtin_riscv_tt_sfpsetcc(v, f, mod)
#define __builtin_rvtt_bh_sfpxfcmpv(a, b, mod) \
    __builtin_riscv_tt_sfpsetcc(a, 0, mod)
#define __builtin_rvtt_bh_sfpxicmps(buf, v, i, x1, x2, mod) \
    __builtin_riscv_tt_sfpsetcc(v, i, mod)

/* BH-specific */
#define __builtin_rvtt_bh_sfparecip(src, mod) __builtin_riscv_tt_sfparecip(src, 0, mod)
#define __builtin_rvtt_bh_sfparecip_lv(live, src, mod) __builtin_riscv_tt_sfparecip_lv(live, src, 0, mod)
#define __builtin_rvtt_bh_sfpgt(src, mod) __builtin_riscv_tt_sfpgt(src, 0, mod)
#define __builtin_rvtt_bh_sfple(src, mod) __builtin_riscv_tt_sfple(src, 0, mod)
#define __builtin_rvtt_bh_sfpmul24(a, b, mod) __builtin_riscv_tt_sfpmul24(a, b, 9, mod)
#define __builtin_rvtt_bh_sfpmul24_lv(live, a, b, mod) __builtin_riscv_tt_sfpmul24_lv(live, a, b, 9, mod)

/* LUT */
#define __builtin_rvtt_sfplut(dst, l0, l1, l2, mod) __builtin_riscv_tt_sfplut(0, 0)
#define __builtin_rvtt_sfplutfp32_3r(dst, l0, l1, l2, mod) __builtin_riscv_tt_sfplutfp32(dst, mod)
#define __builtin_rvtt_sfplutfp32_6r(dst, l0, l1, l2, l4, l5, l6, mod) __builtin_riscv_tt_sfplutfp32(dst, mod)

/* Stochastic rounding */
#define __builtin_rvtt_bh_sfpstochrnd_i(buf, mode, x1, x2, x3, src, mod) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, src, 0, mod)
#define __builtin_rvtt_bh_sfpstochrnd_v(mode, src_b, src_c, mod) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, src_b, src_c, mod)

/* Swap / transpose */
#define __builtin_rvtt_sfpswap(a, b, mod) __builtin_riscv_tt_sfpswap(a, 0, mod)
#define __builtin_rvtt_sfptransp(a, b, c, d) __builtin_riscv_tt_sfptransp(a, 0, 0)

/* SFPSHFT2 */
#define __builtin_rvtt_sfpshft2_e(dst, src, mod) __builtin_riscv_tt_sfpshft2(src, 0, mod)

#endif /* __riscv_xtttensixbh */

/* ---- WH builtins (same pattern, different load/store encoding) ---- */
#ifdef __riscv_xtttensixwh

#define __builtin_rvtt_wh_sfpload(buf, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpload(mod0, mode, addr)
#define __builtin_rvtt_wh_sfpload_lv(buf, live, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpload_lv(live, mod0, mode, addr)
#define __builtin_rvtt_wh_sfpstore(buf, src, mod0, mode, addr, x1, x2) \
    __builtin_riscv_tt_sfpstore(src, mod0, mode, addr)
#define __builtin_rvtt_wh_sfpxloadi(buf, mod0, imm16, x1, x2) \
    __builtin_riscv_tt_sfploadi(mod0, imm16)

#define __builtin_rvtt_wh_sfpmad(a, b, c, mod) __builtin_riscv_tt_sfpmad(a, b, c, mod)
#define __builtin_rvtt_wh_sfpmul(a, b, mod) __builtin_riscv_tt_sfpmul(a, b, 9, mod)
#define __builtin_rvtt_wh_sfpadd(a, b, mod) __builtin_riscv_tt_sfpadd(10, a, b, mod)

#define __builtin_rvtt_wh_sfpsetexp_i(buf, imm12, x1, x2, src) \
    __builtin_riscv_tt_sfpsetexp(src, imm12, 0)
#define __builtin_rvtt_wh_sfpsetexp_v(dst, src) \
    __builtin_riscv_tt_sfpsetexp(src, 0, 0)
#define __builtin_rvtt_wh_sfpsetman_i(buf, imm12, x1, x2, src, mod) \
    __builtin_riscv_tt_sfpsetman(src, imm12, mod)
#define __builtin_rvtt_wh_sfpsetman_v(dst, src) \
    __builtin_riscv_tt_sfpsetman(src, 0, 0)
#define __builtin_rvtt_wh_sfpdivp2(buf, imm12, x1, x2, src, mod) \
    __builtin_riscv_tt_sfpdivp2(src, imm12, mod)
#define __builtin_rvtt_wh_sfpxiadd_i(buf, src, imm12, x1, x2, mod) \
    __builtin_riscv_tt_sfpiadd(src, imm12, mod)
#define __builtin_rvtt_wh_sfpxiadd_v(dst, src, mod) \
    __builtin_riscv_tt_sfpiadd(src, 0, mod)
#define __builtin_rvtt_wh_sfpxfcmps(buf, v, f, x1, x2, mod) \
    __builtin_riscv_tt_sfpsetcc(v, f, mod)
#define __builtin_rvtt_wh_sfpxfcmpv(a, b, mod) \
    __builtin_riscv_tt_sfpsetcc(a, 0, mod)

#endif /* __riscv_xtttensixwh */

/* ---- SFPI control-flow builtins ---- */
/* These are NOT hardware instructions. GCC's SFPI implementation lowers
 * them in the GCC middle-end (gimple-rvtt.cc). For LLVM, we implement them
 * as inline sequences of the primitive CC-stack builtins. */

/* sfpassign_lv: conditional assignment (used in v_if/v_else regions)
 * GCC lowers this to a predicated move. For clang, the _lv builtin
 * variants handle this — sfpassign_lv(dst, src) is just sfpmov_lv. */
#define __builtin_rvtt_sfpassign_lv(live, src) \
    __builtin_riscv_tt_sfpmov_lv(live, src, 0, 0)

/* sfpxvif: begin a v_if region. GCC pushes CC then sets condition.
 * The SFPI C++ API handles this via SFPPUSHC + SFPSETCC, so we
 * define it as a no-op — the C++ wrapper manages the CC stack. */
#define __builtin_rvtt_sfpxvif(cc) /* handled by sfpi.h C++ wrappers */

/* sfpxcondb/sfpxcondi: conditional-branch helpers used by SFPI's
 * v_if/v_elseif implementation. These are GCC gimple builtins that
 * get lowered to SFPSETCC+SFPCOMPC sequences. For clang, the SFPI
 * C++ headers manage this flow directly. Stub as no-ops. */
#define __builtin_rvtt_sfpxcondb(src, mod) /* lowered by sfpi.h */
#define __builtin_rvtt_sfpxcondi(imm, mod) /* lowered by sfpi.h */

/* sfpxbool: boolean operation on CC stack. Stub for now. */
#define __builtin_rvtt_sfpxbool(op, result) (result)

/* sfpxicmpv: integer compare vector — maps to sfpsetcc with int mode */
#define __builtin_rvtt_sfpxicmpv(a, b, mod) \
    __builtin_riscv_tt_sfpsetcc(a, 0, mod)

/* sfpreadlreg/sfpwritelreg: L-register read/write helpers.
 * In GCC, these are direct register accesses. For LLVM, we use inline asm
 * since there's no intrinsic for raw LReg access (the register allocator
 * manages LRegs). */
static inline unsigned int __builtin_rvtt_sfpreadlreg(unsigned int lreg) {
    unsigned int result;
    __asm__ volatile("sfpmov %0, %1, 0" : "=r"(result) : "r"(lreg));
    return result;
}
static inline void __builtin_rvtt_sfpwritelreg(unsigned int lreg, unsigned int val) {
    __asm__ volatile("sfpmov %0, %1, 0" : "=r"(lreg) : "r"(val));
}

/* synth_opcode: emit a raw Tensix opcode. Not an SFPU instruction.
 * Used for rare non-SFPU operations within SFPU kernels. */
#define __builtin_rvtt_synth_opcode(opcode) \
    __asm__ volatile(".word %0" :: "i"(opcode))

/* ttincrwc: increment write counter (Tensix scalar instruction, not SFPU).
 * The write counter manages Dst tile addressing. */
#define __builtin_rvtt_ttincrwc(cr, incr, mask, val) \
    __asm__ volatile("# ttincrwc placeholder" ::: "memory")

/* ttreplay: replay buffer control. Stub for initial bring-up. */
#define __builtin_rvtt_ttreplay(buf, start, len, exec_while_loading) \
    /* replay handled by SFPU replay pass */

/* WH-specific missing builtins */
#ifdef __riscv_xtttensixwh
#define __builtin_rvtt_wh_sfpcast(src, mod) __builtin_riscv_tt_sfpcast(src, 0, mod)
#define __builtin_rvtt_wh_sfpsetsgn_i(buf, imm12, x1, x2, src) \
    __builtin_riscv_tt_sfpsetsgn(src, imm12, 0)
#define __builtin_rvtt_wh_sfpsetsgn_v(dst, src) \
    __builtin_riscv_tt_sfpsetsgn(src, 0, 0)
#define __builtin_rvtt_wh_sfpstochrnd_i(buf, mode, x1, x2, x3, src, mod) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, src, 0, mod)
#define __builtin_rvtt_wh_sfpstochrnd_v(mode, src_b, src_c, mod) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, src_b, src_c, mod)
#define __builtin_rvtt_wh_sfpshft_v(dst, src, mod) \
    __builtin_riscv_tt_sfpshft(src, 0, mod)
#define __builtin_rvtt_wh_sfpconfig_v(src, mod) \
    __builtin_riscv_tt_sfpconfig(0, src, mod)
#endif /* __riscv_xtttensixwh */

/* BH-specific missing builtins */
#ifdef __riscv_xtttensixbh
#define __builtin_rvtt_bh_sfpcast(src, mod) __builtin_riscv_tt_sfpcast(src, 0, mod)
#define __builtin_rvtt_bh_sfpconfig_v(src, mod) \
    __builtin_riscv_tt_sfpconfig(0, src, mod)
#define __builtin_rvtt_bh_sfpxicmpv(a, b, mod) \
    __builtin_riscv_tt_sfpsetcc(a, 0, mod)
#endif /* __riscv_xtttensixbh */

#endif /* __clang__ */
#endif /* SFPI_COMPAT_H */
