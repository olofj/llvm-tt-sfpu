//===-- IntrinsicsRISCVXttSFPU.td - XttSFPU Intrinsics -----*- tablegen -*-===//
//
// LLVM intrinsic definitions for Tenstorrent SFPU instructions.
// Each SFPU instruction maps to one intrinsic (1:1 correspondence).
//
// Intrinsic naming: int_riscv_tt_sfp<mnemonic>
// All operands are i32 (register indices and immediates).
//
// Reference: ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.4
//            ttsim-analysis/ERRATA.md C-006
//
//===----------------------------------------------------------------------===//

let TargetPrefix = "riscv" in {

//--- Load/Store Intrinsics ---

// SFPLOAD: load from Dst to LReg
def int_riscv_tt_sfpload
    : Intrinsic<[llvm_i32_ty],                         // dest LReg
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty], // mod0, addr_mode, addr
                [IntrReadMem, IntrHasSideEffects]>;

// SFPLOADI: load immediate to LReg (Load-format: lreg + mod0 + imm16)
def int_riscv_tt_sfploadi
    : Intrinsic<[llvm_i32_ty],                         // dest LReg
                [llvm_i32_ty, llvm_i32_ty],             // mod0, imm16
                [IntrNoMem, IntrHasSideEffects]>;

// SFPSTORE: store LReg to Dst
def int_riscv_tt_sfpstore
    : Intrinsic<[],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                // lreg_src, mod0, addr_mode, addr
                [IntrWriteMem, IntrHasSideEffects]>;

// SFPLUT: LUT lookup
def int_riscv_tt_sfplut
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty], // mod0, addr_mode, addr
                [IntrReadMem, IntrHasSideEffects]>;

// SFPLOADMACRO: macro load (writes L16)
def int_riscv_tt_sfploadmacro
    : Intrinsic<[],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                // lreg, mod0, addr_mode, addr
                [IntrHasSideEffects]>;

//--- Immediate-16 Arithmetic ---

// SFPMULI: multiply by immediate
def int_riscv_tt_sfpmuli
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty], // lreg_dest, imm16, mod1
                [IntrNoMem, IntrHasSideEffects]>;

// SFPADDI: add immediate
def int_riscv_tt_sfpaddi
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty], // lreg_dest, imm16, mod1
                [IntrNoMem, IntrHasSideEffects]>;

//--- Standard Unary Arithmetic ---

// SFPDIVP2: divide by power of 2 (exponent manipulation)
def int_riscv_tt_sfpdivp2
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty], // lreg_c, imm12, mod1
                [IntrNoMem, IntrHasSideEffects]>;

// SFPEXEXP: extract exponent
def int_riscv_tt_sfpexexp
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPEXMAN: extract mantissa
def int_riscv_tt_sfpexman
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPIADD: integer add/subtract with CC
def int_riscv_tt_sfpiadd
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPSHFT: shift
def int_riscv_tt_sfpshft
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPSETCC: set condition codes
def int_riscv_tt_sfpsetcc
    : Intrinsic<[],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty], // lreg_c, imm12, mod1
                [IntrNoMem, IntrHasSideEffects]>;

// SFPMOV: register move
def int_riscv_tt_sfpmov
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPABS: absolute value
def int_riscv_tt_sfpabs
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPAND: bitwise AND
def int_riscv_tt_sfpand
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPOR: bitwise OR
def int_riscv_tt_sfpor
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPNOT: bitwise NOT
def int_riscv_tt_sfpnot
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPLZ: leading zeros count
def int_riscv_tt_sfplz
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPSETEXP: set exponent
def int_riscv_tt_sfpsetexp
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPSETMAN: set mantissa
def int_riscv_tt_sfpsetman
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

//--- 3-Operand Arithmetic ---

// SFPMAD: multiply-accumulate (dest = src_a * src_b + src_c)
def int_riscv_tt_sfpmad
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                // src_a, src_b, src_c, mod1
                [IntrNoMem, IntrHasSideEffects]>;

// SFPADD: 3-operand add
def int_riscv_tt_sfpadd
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPMUL: 3-operand multiply
def int_riscv_tt_sfpmul
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

//--- CC Stack / Predication ---

// SFPPUSHC: push condition code stack
def int_riscv_tt_sfppushc
    : Intrinsic<[], [], [IntrNoMem, IntrHasSideEffects]>;

// SFPPOPC: pop condition code stack
def int_riscv_tt_sfppopc
    : Intrinsic<[], [], [IntrNoMem, IntrHasSideEffects]>;

// SFPCOMPC: complement condition codes (for else-branch)
def int_riscv_tt_sfpcompc
    : Intrinsic<[], [], [IntrNoMem, IntrHasSideEffects]>;

// SFPENCC: enable condition codes
def int_riscv_tt_sfpencc
    : Intrinsic<[], [llvm_i32_ty, llvm_i32_ty],  // imm12, mod1
                [IntrNoMem, IntrHasSideEffects]>;

// SFPSETSGN: set sign bit
def int_riscv_tt_sfpsetsgn
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

//--- Cross-Lane / Transpose ---

// SFPTRANSP: 4x8 transpose across lanes
def int_riscv_tt_sfptransp
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPXOR: bitwise XOR
def int_riscv_tt_sfpxor
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

//--- Rounding / Cast ---

// SFP_STOCH_RND: stochastic rounding
def int_riscv_tt_sfpstochrnd
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                // rnd_mode, imm8, lreg_src_b, mod1
                [IntrNoMem, IntrHasSideEffects]>;

// SFPCAST: format conversion
def int_riscv_tt_sfpcast
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

//--- Config / Control ---

// SFPCONFIG: write config register
def int_riscv_tt_sfpconfig
    : Intrinsic<[],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty], // imm16, vd, mod1
                [IntrHasSideEffects]>;

// SFPNOP: pipeline NOP
def int_riscv_tt_sfpnop
    : Intrinsic<[], [], [IntrNoMem, IntrHasSideEffects]>;

//--- SFPSWAP: conditional swap ---
def int_riscv_tt_sfpswap
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

//--- SFPSHFT2: cross-lane shift/rotate ---
def int_riscv_tt_sfpshft2
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

//--- SFPLUTFP32: FP32 LUT interpolation ---
def int_riscv_tt_sfplutfp32
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty],  // lreg_c, mod1
                [IntrNoMem, IntrHasSideEffects]>;

//--- BH-Only Intrinsics ---

// SFPMUL24: 23b x 23b integer multiply
def int_riscv_tt_sfpmul24
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPARECIP: approximate reciprocal
def int_riscv_tt_sfparecip
    : Intrinsic<[llvm_i32_ty],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPGT: greater-than comparison
def int_riscv_tt_sfpgt
    : Intrinsic<[],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

// SFPLE: less-or-equal comparison
def int_riscv_tt_sfple
    : Intrinsic<[],
                [llvm_i32_ty, llvm_i32_ty, llvm_i32_ty],
                [IntrNoMem, IntrHasSideEffects]>;

} // TargetPrefix = "riscv"
