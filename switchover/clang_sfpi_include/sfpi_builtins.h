/*
 * sfpi_builtins.h — Clang-compatible replacement for tt-metal's sfpi_builtins.h
 *
 * This file replaces runtime/sfpi/include/sfpi_builtins.h when compiling with
 * clang. It maps the generic __builtin_rvtt_* macros directly to LLVM
 * __builtin_riscv_tt_* builtins, without the self-referencing macro trick or
 * ckernel::instrn_buffer argument that GCC's version uses.
 *
 * The build system must add this directory to -I BEFORE runtime/sfpi/include
 * so this file is found first:
 *   -I switchover/clang_sfpi_include -I runtime/sfpi/include
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#ifndef __clang__
/* Not clang — fall through to the real sfpi_builtins.h.
 * This should not happen if include paths are configured correctly. */
#include_next "sfpi_builtins.h"
#else

namespace sfpi {

/* ---- Generic builtins (architecture-independent) ---- */
/* These two use a self-referencing macro trick in GCC's sfpi_builtins.h
 * that doesn't work in clang. Map directly to LLVM builtins. */

#define __builtin_rvtt_sfpxicmps(v, i, mod1) \
    __builtin_riscv_tt_sfpsetcc(v, i, mod1)

#define __builtin_rvtt_sfpshft_i(dst, imm12, mod1) \
    __builtin_riscv_tt_sfpshft(dst, imm12, mod1)

/* ---- Architecture-dispatched builtins ---- */

#if defined(__riscv_xtttensixbh)
/* ======== Blackhole dispatches ======== */

/* Load/Store — GCC's versions take instrn_buffer; LLVM doesn't need it */
#define __builtin_rvtt_sfpload(mod0, mode, addr) \
    __builtin_riscv_tt_sfpload(mod0, mode, addr)
#define __builtin_rvtt_sfpload_lv(live, mod0, mode, addr) \
    __builtin_riscv_tt_sfpload_lv(live, mod0, mode, addr)
#define __builtin_rvtt_sfpxloadi(mod0, imm16) \
    __builtin_riscv_tt_sfploadi(mod0, imm16)
#define __builtin_rvtt_sfpxloadi_lv(live, mod0, imm16) \
    __builtin_riscv_tt_sfploadi(mod0, imm16)
#define __builtin_rvtt_sfpstore(src, mod0, mode, addr) \
    __builtin_riscv_tt_sfpstore(src, mod0, mode, addr)

/* 3-operand arithmetic — implicit constant register args */
#define __builtin_rvtt_sfpmul(va, vb, mod1) \
    __builtin_riscv_tt_sfpmul(va, vb, 9, mod1)
#define __builtin_rvtt_sfpmul_lv(live, va, vb, mod1) \
    __builtin_riscv_tt_sfpmul_lv(live, va, vb, 9, mod1)
#define __builtin_rvtt_sfpadd(va, vb, mod1) \
    __builtin_riscv_tt_sfpadd(10, va, vb, mod1)
#define __builtin_rvtt_sfpadd_lv(live, va, vb, mod1) \
    __builtin_riscv_tt_sfpadd_lv(live, 10, va, vb, mod1)
#define __builtin_rvtt_sfpmad(va, vb, vc, mod1) \
    __builtin_riscv_tt_sfpmad(va, vb, vc, mod1)
#define __builtin_rvtt_sfpmad_lv(live, va, vb, vc, mod1) \
    __builtin_riscv_tt_sfpmad_lv(live, va, vb, vc, mod1)

/* Comparison — map to sfpsetcc */
#define __builtin_rvtt_sfpxfcmps(v, f, mod1) \
    __builtin_riscv_tt_sfpsetcc(v, f, mod1)
#define __builtin_rvtt_sfpxfcmpv(v1, v2, mod1) \
    __builtin_riscv_tt_sfpsetcc(v1, 0, mod1)

/* Unary with immediate — argument reordering */
#define __builtin_rvtt_sfpsetexp_i(imm12, src) \
    __builtin_riscv_tt_sfpsetexp(src, imm12, 0)
#define __builtin_rvtt_sfpsetexp_v(dst, src) \
    __builtin_riscv_tt_sfpsetexp(src, 0, 0)

#define __builtin_rvtt_sfpsetman_i(imm12, src, mod) \
    __builtin_riscv_tt_sfpsetman(src, imm12, mod)
#define __builtin_rvtt_sfpsetman_v(dst, src) \
    __builtin_riscv_tt_sfpsetman(src, 0, 0)

#define __builtin_rvtt_sfpdivp2(imm12, src, mod1) \
    __builtin_riscv_tt_sfpdivp2(src, imm12, mod1)
#define __builtin_rvtt_sfpdivp2_lv(live, imm12, src, mod1) \
    __builtin_riscv_tt_sfpdivp2_lv(live, src, imm12, mod1)

/* Integer add — GCC arg order: src, imm12, mod1 */
#define __builtin_rvtt_sfpxiadd_i(src, imm12, mod1) \
    __builtin_riscv_tt_sfpiadd(src, imm12, mod1)
#define __builtin_rvtt_sfpxiadd_v(dst, src, mod1) \
    __builtin_riscv_tt_sfpiadd(src, 0, mod1)

/* Sign */
#define __builtin_rvtt_sfpsetsgn_i(imm12, src) \
    __builtin_riscv_tt_sfpsetsgn(src, imm12, 0)
#define __builtin_rvtt_sfpsetsgn_v(dst, src) \
    __builtin_riscv_tt_sfpsetsgn(src, 0, 0)

/* Cast */
#define __builtin_rvtt_sfpcast(src, mod1) \
    __builtin_riscv_tt_sfpcast(src, 0, mod1)

/* Stochastic rounding */
#define __builtin_rvtt_sfpstochrnd_i(mode, imm8, srcc, mod1) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, srcc, 0, mod1)
#define __builtin_rvtt_sfpstochrnd_v(mode, srcb, srcc, mod1) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, srcb, srcc, mod1)

/* Config */
#define __builtin_rvtt_sfpconfig_v(l0, config_dest) \
    __builtin_riscv_tt_sfpconfig(0, l0, config_dest)

/* BH-only instructions */
#define __builtin_rvtt_sfpmov_config(src) \
    __builtin_riscv_tt_sfpmov(src, 0, 0)
#define __builtin_rvtt_sfparecip(src, mod) \
    __builtin_riscv_tt_sfparecip(src, 0, mod)
#define __builtin_rvtt_sfparecip_lv(live, src, mod) \
    __builtin_riscv_tt_sfparecip_lv(live, src, 0, mod)
#define __builtin_rvtt_sfpmul24(a, b, mod) \
    __builtin_riscv_tt_sfpmul24(a, b, 9, mod)
#define __builtin_rvtt_sfpmul24_lv(live, a, b, mod) \
    __builtin_riscv_tt_sfpmul24_lv(live, a, b, 9, mod)

#elif defined(__riscv_xtttensixwh)
/* ======== Wormhole dispatches ======== */

/* Load/Store */
#define __builtin_rvtt_sfpload(mod0, mode, addr) \
    __builtin_riscv_tt_sfpload(mod0, mode, addr)
#define __builtin_rvtt_sfpload_lv(live, mod0, mode, addr) \
    __builtin_riscv_tt_sfpload_lv(live, mod0, mode, addr)
#define __builtin_rvtt_sfpxloadi(mod0, imm16) \
    __builtin_riscv_tt_sfploadi(mod0, imm16)
#define __builtin_rvtt_sfpstore(src, mod0, mode, addr) \
    __builtin_riscv_tt_sfpstore(src, mod0, mode, addr)

/* 3-operand arithmetic */
#define __builtin_rvtt_sfpmul(va, vb, mod1) \
    __builtin_riscv_tt_sfpmul(va, vb, 9, mod1)
#define __builtin_rvtt_sfpadd(va, vb, mod1) \
    __builtin_riscv_tt_sfpadd(10, va, vb, mod1)
#define __builtin_rvtt_sfpmad(va, vb, vc, mod1) \
    __builtin_riscv_tt_sfpmad(va, vb, vc, mod1)

/* Comparison */
#define __builtin_rvtt_sfpxfcmps(v, f, mod1) \
    __builtin_riscv_tt_sfpsetcc(v, f, mod1)
#define __builtin_rvtt_sfpxfcmpv(v1, v2, mod1) \
    __builtin_riscv_tt_sfpsetcc(v1, 0, mod1)

/* Unary with immediate */
#define __builtin_rvtt_sfpsetexp_i(imm12, src) \
    __builtin_riscv_tt_sfpsetexp(src, imm12, 0)
#define __builtin_rvtt_sfpsetexp_v(dst, src) \
    __builtin_riscv_tt_sfpsetexp(src, 0, 0)

#define __builtin_rvtt_sfpsetman_i(imm12, src, mod) \
    __builtin_riscv_tt_sfpsetman(src, imm12, mod)
#define __builtin_rvtt_sfpsetman_v(dst, src) \
    __builtin_riscv_tt_sfpsetman(src, 0, 0)

#define __builtin_rvtt_sfpdivp2(imm12, src, mod1) \
    __builtin_riscv_tt_sfpdivp2(src, imm12, mod1)

#define __builtin_rvtt_sfpxiadd_i(src, imm12, mod1) \
    __builtin_riscv_tt_sfpiadd(src, imm12, mod1)
#define __builtin_rvtt_sfpxiadd_v(dst, src, mod1) \
    __builtin_riscv_tt_sfpiadd(src, 0, mod1)

#define __builtin_rvtt_sfpsetsgn_i(imm12, src) \
    __builtin_riscv_tt_sfpsetsgn(src, imm12, 0)
#define __builtin_rvtt_sfpsetsgn_v(dst, src) \
    __builtin_riscv_tt_sfpsetsgn(src, 0, 0)

#define __builtin_rvtt_sfpcast(src, mod1) \
    __builtin_riscv_tt_sfpcast(src, 0, mod1)

#define __builtin_rvtt_sfpstochrnd_i(mode, imm8, srcc, mod1) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, srcc, 0, mod1)
#define __builtin_rvtt_sfpstochrnd_v(mode, srcb, srcc, mod1) \
    __builtin_riscv_tt_sfpstochrnd(mode, 0, srcb, srcc, mod1)

#define __builtin_rvtt_sfpconfig_v(l0, config_dest) \
    __builtin_riscv_tt_sfpconfig(0, l0, config_dest)

#endif /* architecture dispatch */

} /* namespace sfpi */

#endif /* __clang__ */
