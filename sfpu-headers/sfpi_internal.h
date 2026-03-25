// sfpi_internal.h — LLVM intrinsic declarations for SFPU instructions
//
// This header provides C/C++ callable intrinsics that map 1:1 to SFPU
// hardware instructions. Used by sfpi.h to implement the SFPI API.
//
// These intrinsics are compatible with the sfpi-gcc builtins but use
// LLVM's __builtin_riscv_tt_* naming convention.
//
// Reference: ttsim-analysis/ERRATA.md C-006 (opcode map)
//            ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.4

#ifndef SFPI_INTERNAL_H
#define SFPI_INTERNAL_H

#ifdef __cplusplus
extern "C" {
#endif

// --- Load/Store intrinsics ---
// SFPLOAD: load from Dst to LReg
int __builtin_riscv_tt_sfpload(int mod0, int addr_mode, int addr)
    __attribute__((always_inline));

// SFPLOADI: load immediate to LReg
int __builtin_riscv_tt_sfploadi(int imm16, int mod1)
    __attribute__((always_inline));

// SFPSTORE: store LReg to Dst
void __builtin_riscv_tt_sfpstore(int lreg_src, int mod0, int addr_mode, int addr)
    __attribute__((always_inline));

// SFPLUT: LUT lookup
int __builtin_riscv_tt_sfplut(int mod0, int addr_mode, int addr)
    __attribute__((always_inline));

// SFPLOADMACRO: macro load (writes L16)
void __builtin_riscv_tt_sfploadmacro(int lreg, int mod0, int addr_mode, int addr)
    __attribute__((always_inline));

// --- Immediate-16 arithmetic ---
int __builtin_riscv_tt_sfpmuli(int lreg_dest, int imm16, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpaddi(int lreg_dest, int imm16, int mod1)
    __attribute__((always_inline));

// --- Standard unary arithmetic ---
int __builtin_riscv_tt_sfpdivp2(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpexexp(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpexman(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpiadd(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpshft(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

void __builtin_riscv_tt_sfpsetcc(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpmov(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpabs(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpand(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpor(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpnot(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfplz(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpsetexp(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpsetman(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

// --- 3-operand arithmetic ---
int __builtin_riscv_tt_sfpmad(int src_a, int src_b, int src_c, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpadd(int src_a, int src_b, int src_c, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpmul(int src_a, int src_b, int src_c, int mod1)
    __attribute__((always_inline));

// --- CC stack / predication ---
void __builtin_riscv_tt_sfppushc(void)
    __attribute__((always_inline));

void __builtin_riscv_tt_sfppopc(void)
    __attribute__((always_inline));

void __builtin_riscv_tt_sfpcompc(void)
    __attribute__((always_inline));

void __builtin_riscv_tt_sfpencc(int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpsetsgn(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

// --- Cross-lane / transpose ---
int __builtin_riscv_tt_sfptransp(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpxor(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

// --- Rounding / cast ---
int __builtin_riscv_tt_sfpstochrnd(int rnd_mode, int imm8, int lreg_src_b, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfpcast(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

// --- Config / control ---
void __builtin_riscv_tt_sfpconfig(int imm16, int vd, int mod1)
    __attribute__((always_inline));

void __builtin_riscv_tt_sfpnop(void)
    __attribute__((always_inline));

// --- Swap ---
int __builtin_riscv_tt_sfpswap(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

// --- Cross-lane shift ---
int __builtin_riscv_tt_sfpshft2(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

// --- LUT FP32 ---
int __builtin_riscv_tt_sfplutfp32(int lreg_c, int mod1)
    __attribute__((always_inline));

// --- BH-only intrinsics ---
int __builtin_riscv_tt_sfpmul24(int src_a, int src_b, int src_c, int mod1)
    __attribute__((always_inline));

int __builtin_riscv_tt_sfparecip(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

void __builtin_riscv_tt_sfpgt(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

void __builtin_riscv_tt_sfple(int lreg_c, int imm12, int mod1)
    __attribute__((always_inline));

#ifdef __cplusplus
}
#endif

// --- SFPU modifier constants ---
// From ttsim-analysis/ERRATA.md C-020

// SFPLOADI modes (C-007)
#define SFPLOADI_MOD1_FLOATB    0
#define SFPLOADI_MOD1_FLOATA    1
#define SFPLOADI_MOD1_USHORT    2
#define SFPLOADI_MOD1_SHORT     4
#define SFPLOADI_MOD1_UPPER     8
#define SFPLOADI_MOD1_LOWER     10

// SFPSETCC modes
#define SFPSETCC_MOD1_LREG_LT0     0
#define SFPSETCC_MOD1_IMM_BIT0     1
#define SFPSETCC_MOD1_LREG_NE0     2
#define SFPSETCC_MOD1_LREG_GTE0    4
#define SFPSETCC_MOD1_LREG_EQ0     6
#define SFPSETCC_MOD1_COMP         8

// SFPEXEXP modes
#define SFPEXEXP_MOD1_DEBIAS           0
#define SFPEXEXP_MOD1_NODEBIAS         1
#define SFPEXEXP_MOD1_SET_CC_SGN_EXP   2
#define SFPEXEXP_MOD1_SET_CC_COMP_EXP  8

// SFPIADD modifier bitfield (C-008)
#define SFPXIADD_MOD1_SIGNED      (1 << 3)
#define SFPXIADD_MOD1_IS_SUB      (1 << 4)
#define SFPXIADD_MOD1_12BIT       (1 << 5)
#define SFPXIADD_MOD1_16BIT       (1 << 6)
#define SFPXIADD_MOD1_DST_UNUSED  (1 << 7)

// SFPSWAP modes (C-025)
#define SFPSWAP_MOD1_SWAP     0
#define SFPSWAP_MOD1_MIN      1
#define SFPSWAP_MOD1_ARGMIN   2
#define SFPSWAP_MOD1_ARGMAX   3
#define SFPSWAP_MOD1_MAX      9

// SFPSHFT modes (C-005)
#define SFPSHFT_MOD1_SHFT_IMM_WH  1   // WH immediate shift
#define SFPSHFT_MOD1_SHFT_IMM_BH  5   // BH immediate shift

// SFPCAST modes (C-019)
#define SFPCAST_MOD1_FP32_TO_FP16A   0
#define SFPCAST_MOD1_FP32_TO_FP16B   1
#define SFPCAST_MOD1_FP16A_TO_FP32   2
#define SFPCAST_MOD1_FP16B_TO_FP32   3
#define SFPCAST_MOD1_SM32_TO_INT32   4   // BH only
#define SFPCAST_MOD1_INT32_TO_SM32   5   // BH only

// CREG (constant register) indices (C-002)
#define CREG_IDX_0837   8    // L8  = 0.8373
#define CREG_IDX_0      9    // L9  = 0.0
#define CREG_IDX_1      10   // L10 = 1.0
#define CREG_IDX_NEG1   11   // L11 = -1.0 (convention, writable)
#define CREG_IDX_HALF   12   // L12 = 1/512 (convention, writable)
#define CREG_IDX_NEG067 13   // L13 = -0.6749 (convention, writable)
#define CREG_IDX_NEG034 14   // L14 = -0.3448 (convention, writable)
#define CREG_IDX_LANEID 15   // L15 = lane ID (2*i)

#endif // SFPI_INTERNAL_H
