/*
 * sfpi_builtins.h — LLVM-compatible builtin mapping layer
 *
 * Replaces the system sfpi_builtins.h which maps short-form builtins
 * to long-form GCC builtins. This version maps directly to LLVM
 * intrinsics via the __builtin_riscv_tt_* builtins.
 *
 * The system sfpi.h uses short-form builtins like:
 *   __builtin_rvtt_sfpload(addr, mod0, mode)
 * The system sfpi_builtins.h expands them to long-form GCC builtins:
 *   __builtin_rvtt_sfpload(instrn_buffer, addr, 0, 0, mod0, mode)
 * This file short-circuits that to LLVM builtins:
 *   __builtin_riscv_tt_sfpload(mod0, mode, addr)
 */

#pragma once

#ifdef __clang__

namespace sfpi {

/* --- Loads --- */
#define __builtin_rvtt_sfpload(addr, mod0, mode) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpload(mod0, mode, addr))

/* sfpxloadi: extended load immediate.
 * For 16-bit modes (FLOATB, FLOATA, SHORT, USHORT): single SFPLOADI.
 * For 32-bit modes (INT32=16, UINT32=17, FLOAT=18): decompose into UPPER+LOWER.
 * The hardware's 2-word encoding for 32-bit modes isn't supported by our backend,
 * so we decompose at the C level. UPPER loads bits[31:16], LOWER ORs bits[15:0]. */
#define __builtin_rvtt_sfpxloadi_32(imm) \
    (((imm) & 0xFFFF) != 0 \
        ? (__builtin_riscv_tt_sfploadi(8, ((imm) >> 16) & 0xFFFF), \
           static_cast<__xtt_vector>(__builtin_riscv_tt_sfploadi(10, (imm) & 0xFFFF))) \
        : static_cast<__xtt_vector>(__builtin_riscv_tt_sfploadi(8, ((imm) >> 16) & 0xFFFF)))
#define __builtin_rvtt_sfpxloadi(imm, mod0) \
    ((mod0) >= 16 && (unsigned)(imm) > 0xFFFFu \
        ? __builtin_rvtt_sfpxloadi_32(imm) \
        : static_cast<__xtt_vector>(__builtin_riscv_tt_sfploadi(mod0, imm)))

/* --- Store --- */
#define __builtin_rvtt_sfpstore(src, addr, mod0, mode) \
    __builtin_riscv_tt_sfpstore(src, mod0, mode, addr)

/* --- Arithmetic --- */
#define __builtin_rvtt_sfpmad(a, b, c, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpmad(a, b, c, mod))
#define __builtin_rvtt_sfpmul(a, b, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpmul(a, b, 9, mod))
#define __builtin_rvtt_sfpadd(a, b, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpadd(10, a, b, mod))

/* --- Integer arithmetic --- */
#define __builtin_rvtt_sfpxiadd_v(dst, src, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpiadd(src, 0, mod))
#define __builtin_rvtt_sfpxiadd_i(src, imm, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpiadd(src, imm, mod))

/* --- Shift --- */
#define __builtin_rvtt_sfpshft_i(src, imm, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpshft(src, imm, mod))

/* --- Comparisons (set CC, return dummy 0) --- */
#define __builtin_rvtt_sfpxfcmps(v, f, mod) \
    (__builtin_riscv_tt_sfpxfcmps(v, f, mod), 0)
#define __builtin_rvtt_sfpxfcmpv(a, b, mod) \
    (__builtin_riscv_tt_sfpsetcc(a, 0, mod), 0)
#define __builtin_rvtt_sfpxicmps(v, i, mod) \
    (__builtin_riscv_tt_sfpxfcmps(v, i, mod), 0)

/* --- Config --- */
#define __builtin_rvtt_sfpwriteconfig_v(t, src) \
    __builtin_riscv_tt_sfpconfig(0, src, t)

/* --- Set exp/man/sgn (immediate forms) --- */
#define __builtin_rvtt_sfpsetexp_i(src, imm, mod1) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpsetexp(src, imm, mod1))
#define __builtin_rvtt_sfpsetman_i(src, imm, mod1) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpsetman(src, imm, mod1))
#define __builtin_rvtt_sfpsetsgn_i(src, imm, mod1) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpsetsgn(src, imm, mod1))
#define __builtin_rvtt_sfpdivp2(src, imm, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpdivp2(src, imm, mod))
/* Caller passes (src, imm, mod1=format, rnd_mode=rounding).
 * The intrinsic takes (rnd_mode, imm5, src_b, src_c, mod1). */
#define __builtin_rvtt_sfpstochrnd_i(src, imm, mod1, rnd_mode) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpstochrnd(rnd_mode, imm, src, src, mod1))

/* --- Set exp/man/sgn (vector forms) --- */
/* sfpsetexp_v: HW does dest = src_c_mantissa | dest_exponent.
 * So exp goes to live (dest), v goes to src_c. */
#define __builtin_rvtt_sfpsetexp_v(v, exp, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpsetexp_lv((unsigned int)(exp), (unsigned int)(v), 0, mod))
#define __builtin_rvtt_sfpsetman_v(v, man, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpsetman(v, 0, mod))
#define __builtin_rvtt_sfpsetsgn_v(v, sgn, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpsetsgn(v, 0, mod))
#define __builtin_rvtt_sfpstochrnd_v(mode, src_b, src_c, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpstochrnd(mode, 0, src_b, src_c, mod))

/* --- 24-bit multiply --- */
#define __builtin_rvtt_sfpmul24(a, b, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpmul24(a, b, 9, mod))

/* --- Misc --- */
#define __builtin_rvtt_sfparecip(src, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfparecip(src, 0, mod))
#define __builtin_rvtt_sfpcast(src, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpcast(src, 0, mod))
#define __builtin_rvtt_sfpreadconfig(mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpreadlreg(mod))
#define __builtin_rvtt_sfpxicmpv(a, b, mod) \
    (__builtin_riscv_tt_sfpsetcc(a, 0, mod), 0)
/* sfpshft_v: dest is read-modify-write (value), lreg_c is shift amount */
#define __builtin_rvtt_sfpshft_v(dst, src, mod) \
    static_cast<__xtt_vector>(__builtin_riscv_tt_sfpshft_lv((unsigned int)(dst), (unsigned int)(src), 0, mod))

} // namespace sfpi

#else /* GCC — use original long-form mapping */

namespace sfpi {

#define __builtin_rvtt_sfpxicmps(src, imm, mod1) __builtin_rvtt_sfpxicmps(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpxfcmps(src, imm, mod1) __builtin_rvtt_sfpxfcmps(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpxiadd_i(src, imm, mod1) __builtin_rvtt_sfpxiadd_i(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpxloadi(imm, mod0) __builtin_rvtt_sfpxloadi(ckernel::instrn_buffer, imm, 0, 0, mod0)
#define __builtin_rvtt_sfpshft_i(src, imm, mod1) __builtin_rvtt_sfpshft_i(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpload(addr, mod0, mode) __builtin_rvtt_sfpload(ckernel::instrn_buffer, addr, 0, 0, mod0, mode)
#define __builtin_rvtt_sfpstore(src, addr, mod0, mode) __builtin_rvtt_sfpstore(ckernel::instrn_buffer, src, addr, 0, 0, mod0, mode)
#define __builtin_rvtt_sfpsetexp_i(src, imm, mod1) __builtin_rvtt_sfpsetexp_i(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpsetman_i(src, imm, mod1) __builtin_rvtt_sfpsetman_i(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpsetsgn_i(src, imm, mod1) __builtin_rvtt_sfpsetsgn_i(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpdivp2(src, imm, mod1) __builtin_rvtt_sfpdivp2(ckernel::instrn_buffer, src, imm, 0, 0, mod1)
#define __builtin_rvtt_sfpstochrnd_i(src, imm, mod1, mode) __builtin_rvtt_sfpstochrnd_i(ckernel::instrn_buffer, src, imm, 0, 0, mod1, mode)

} // namespace sfpi

#endif /* __clang__ */
