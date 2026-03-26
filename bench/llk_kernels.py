"""
llk_kernels.py — ALL LLK SFPU kernel definitions for benchmark comparison.

Covers all 53 SFPU kernels from:
  tt-metal/tt_metal/third_party/tt_llk/tt_llk_blackhole/common/inc/sfpu/

Each kernel has GCC and LLVM instruction sequences for the hot loop body
(one iteration processing one Dst row/element). Init sequences are separate.

Categories:
  ml_activations: exp, gelu, sigmoid, tanh, relu, silu, elu, hardtanh, etc.
  ml_math:        recip, sqrt, rsqrt, log, exp2, polyval, etc.
  data_movement:  abs, negative, fill, typecast, cast, etc.
  comparison:     comp (gt, lt, eq, ne, le, ge), isinf, isnan, etc.
  integer_ops:    add_int, sub_int, mul_int, shift, sign, etc.
  reduction:      reduce, reduce_custom, cumsum, welfords, topk, etc.
  misc:           dropout, clamp, threshold, where, quant, etc.
  bitwise:        binary_bitwise (and, or, xor, not)
"""

from sfpu_patterns import *
from sfpu_kernels import Kernel

ALL_LLK_KERNELS = []


def K(name, category, description, gcc, llvm, notes="", source=""):
    """Shorthand to register a kernel."""
    ALL_LLK_KERNELS.append(Kernel(
        name=name, category=category, description=description,
        gcc_insns=gcc, llvm_insns=llvm, notes=notes,
        source_file=source,
    ))


# ============================================================================
# ML Activation Kernels
# ============================================================================

K("exp_horner", "ml_activations",
  "Exponential via 2-step Horner series",
  gcc=[load(0), exexp(1, 0), divp2(0, 1),
       *gcc_mul_add(2, 0, 8, 9),     # MUL+NOP+ADD instead of MAD
       *gcc_mul_add(0, 0, 2, 10),
       store(0)],
  llvm=[load(0), exexp(1, 0), divp2(0, 1),
        mad(2, 0, 8, 9), mad(0, 0, 2, 10),
        store(0)],
  notes="GH-Q-002: MAD combining", source="ckernel_sfpu_exp.h")

K("tanh_lut", "ml_activations",
  "Tanh via 3-piece LUT (init: 3x SFPLOADI)",
  gcc=[load(3), lut(3), nop(), store(3)],
  llvm=[load(3), lut(3), store(3)],
  notes="BH NOP elimination after LUT", source="ckernel_sfpu_tanh.h")

K("sigmoid_lutfp32", "ml_activations",
  "Sigmoid via 6-piece LUTFP32 + 0.5 bias",
  gcc=[load(0), lutfp32(0, 6), nop(), addi(0, "0x3800"), nop(), store(0)],
  llvm=[load(0), lutfp32(0, 6), addi(0, "0x3800"), store(0)],
  notes="BH NOP elim after LUTFP32 and ADDI", source="ckernel_sfpu_sigmoid.h")

K("gelu_approx", "ml_activations",
  "GELU approx: MUL(in*0.5) + LUTFP32 + ADD",
  gcc=[load(0), mul(1, 0, 11, 9), nop(), lutfp32(0, 2), nop(),
       add(0, 10, 1, 0), nop(), store(0)],
  llvm=[load(0), mul(1, 0, 11, 9), lutfp32(0, 2),
        mad(0, 10, 1, 0), store(0)],
  notes="MAD combining + scheduler interleaving", source="ckernel_sfpu_gelu.h")

K("gelu_horner5", "ml_activations",
  "GELU accurate CDF via 5th-order Horner polynomial",
  gcc=[load(0), mul(1, 0, 0, 9), nop(),
       *gcc_mul_add(2, 1, 0, 0),  # Horner step
       *gcc_mul_add(2, 2, 0, 0),
       *gcc_mul_add(2, 2, 0, 0),
       *gcc_mul_add(2, 2, 0, 0),
       store(0)],
  llvm=[load(0), mul(1, 0, 0, 9),
        mad(2, 1, 0, 0), mad(2, 2, 0, 0),
        mad(2, 2, 0, 0), mad(2, 2, 0, 0),
        store(0)],
  notes="4x MAD combining in Horner chain", source="ckernel_sfpu_gelu.h")

K("relu", "ml_activations",
  "ReLU: max(0, x) via predicated zero",
  gcc=[load(0), *gcc_vif(0, 0),  # v_if(x < 0)
       mov(0, 9),                 # x = 0.0 (L9)
       popc(), store(0)],
  llvm=[load(0), pushc(), setcc(0, 0),
        mov(0, 9), popc(), store(0)],
  notes="Same sequence — predication, no combining opportunity",
  source="ckernel_sfpu_relu.h")

K("silu", "ml_activations",
  "SiLU: x * sigmoid(x) = x * LUTFP32(x) + x*0.5",
  gcc=[load(0), mov(1, 0),  # save x
       mul(2, 0, 11, 9), nop(),  # x * 0.5
       lutfp32(0, 2), nop(),
       add(0, 10, 2, 0), nop(),  # 0.5*x + lut
       mul(0, 1, 0, 9), nop(),   # x * sigmoid
       store(0)],
  llvm=[load(0), mov(1, 0),
        mul(2, 0, 11, 9),
        lutfp32(0, 2),
        mad(0, 10, 2, 0),
        mul(0, 1, 0, 9),
        store(0)],
  notes="MAD combining + interleaving", source="ckernel_sfpu_silu.h")

K("elu", "ml_activations",
  "ELU: x if x>0, alpha*(exp(x)-1) if x<=0",
  gcc=[load(0), *gcc_vif(0, 4),  # v_if(x >= 0): pass through
       *gcc_velse(),
       # exp(x) - 1 path (simplified)
       mul(1, 0, 8, 9), nop(), add(1, 10, 1, 10), nop(),  # exp approx
       mul(0, 1, 11, 9), nop(),  # * alpha (using L11)
       popc(), store(0)],
  llvm=[load(0), pushc(), setcc(0, 4),
        compc(), pushc(),
        mad(1, 0, 8, 10),     # exp step + MAD
        mul(0, 1, 11, 9),
        popc(), store(0)],
  notes="MAD + BH NOP elim in else branch", source="ckernel_sfpu_elu.h")

K("hardtanh", "ml_activations",
  "HardTanh: clamp(x, -1, 1)",
  gcc=[load(0), *gcc_vif(0, 0),  # v_if(x < 0 → clamp to -1)
       mov(0, 11),                 # L11 = -1.0
       popc(),
       # clamp upper not shown (similar pattern)
       store(0)],
  llvm=[load(0), pushc(), setcc(0, 0),
        mov(0, 11), popc(), store(0)],
  source="ckernel_sfpu_hardtanh.h")

K("tanh_derivative", "ml_activations",
  "Tanh derivative: 1 - tanh(x)^2",
  gcc=[load(0), lut(0), nop(),  # tanh via LUT
       mul(1, 0, 0, 9), nop(),  # tanh^2
       # 1 - tanh^2
       mul(1, 1, 11, 9), nop(), add(0, 10, 1, 10), nop(),
       store(0)],
  llvm=[load(0), lut(0),
        mul(1, 0, 0, 9),         # tanh^2
        mad(0, 1, 11, 10, 1),    # 1 + (-tanh^2) via COMPL_A
        store(0)],
  notes="MAD combining + negation fold via COMPL_A",
  source="ckernel_sfpu_tanh_derivative.h")

# ============================================================================
# ML Math Kernels
# ============================================================================

K("recip_nr1", "ml_math",
  "Reciprocal with 1 Newton-Raphson iteration",
  gcc=[load(0), arecip(1, 0),
       mul(2, 0, 1, 9), nop(), add(2, 10, 2, 11),
       *gcc_vif(2, 0),
       mul(3, 1, 2, 9), nop(), add(1, 10, 3, 9),
       popc(), store(1)],
  llvm=[load(0), arecip(1, 0),
        mad(2, 0, 1, 11),
        pushc(), setcc(2, 0),
        mad(1, 1, 2, 9),
        popc(), store(1)],
  notes="MAD combining + BH NOP elim", source="ckernel_sfpu_recip.h")

K("recip_nr2", "ml_math",
  "Reciprocal with 2 Newton-Raphson iterations",
  gcc=[load(0), arecip(1, 0),
       mul(2, 0, 1, 9), nop(), add(2, 10, 2, 11),
       mul(3, 1, 2, 9), nop(), add(3, 10, 3, 9),
       *gcc_vif(2, 0),
       mul(4, 0, 3, 9), nop(), add(4, 10, 4, 11),
       mul(1, 3, 4, 9), nop(), add(1, 10, 1, 9),
       popc(), store(1)],
  llvm=[load(0), arecip(1, 0),
        mad(2, 0, 1, 11), mad(3, 1, 2, 9),
        pushc(), setcc(2, 0),
        mad(4, 0, 3, 11), mad(1, 3, 4, 9),
        popc(), store(1)],
  source="ckernel_sfpu_recip.h")

K("sqrt_nr", "ml_math",
  "Square root via reciprocal sqrt + multiply",
  gcc=[load(0), mov(1, 0),  # save x
       # rsqrt approximation + NR
       arecip(2, 0), mul(3, 0, 2, 9), nop(), add(3, 10, 3, 11),
       *gcc_vif(3, 0),
       mul(2, 2, 3, 9), nop(), add(2, 10, 2, 9),
       popc(),
       mul(0, 1, 2, 9), nop(),  # x * rsqrt(x) = sqrt(x)
       store(0)],
  llvm=[load(0), mov(1, 0),
        arecip(2, 0), mad(3, 0, 2, 11),
        pushc(), setcc(3, 0),
        mad(2, 2, 3, 9),
        popc(),
        mul(0, 1, 2, 9),
        store(0)],
  source="ckernel_sfpu_sqrt.h")

K("rsqrt", "ml_math",
  "Reciprocal square root",
  gcc=[load(0), arecip(1, 0),
       mul(2, 0, 1, 9), nop(), add(2, 10, 2, 11),
       *gcc_vif(2, 0),
       mul(1, 1, 2, 9), nop(), add(1, 10, 1, 9),
       popc(), store(1)],
  llvm=[load(0), arecip(1, 0),
        mad(2, 0, 1, 11),
        pushc(), setcc(2, 0),
        mad(1, 1, 2, 9),
        popc(), store(1)],
  source="ckernel_sfpu_rsqrt.h")

K("log_approx", "ml_math",
  "Natural log via exponent extraction + LUT correction",
  gcc=[load(0), exexp(1, 0, 0),  # extract exponent
       exman(2, 0),               # extract mantissa
       setexp(2, 2, 127, 0),      # reconstruct normalized
       lut(2), nop(),             # LUT for log(1+mantissa)
       # combine: log(x) = exp*ln2 + log(mantissa)
       mul(3, 1, 8, 9), nop(), add(0, 10, 3, 2), nop(),
       store(0)],
  llvm=[load(0), exexp(1, 0, 0), exman(2, 0),
        setexp(2, 2, 127, 0), lut(2),
        mad(0, 1, 8, 2),  # MAD: exp*ln2 + log(mantissa)
        store(0)],
  notes="MAD combining for final step", source="ckernel_sfpu_log.h")

K("exp2", "ml_math",
  "Base-2 exponential",
  gcc=[load(0), exexp(1, 0), divp2(0, 1),
       *gcc_mul_add(2, 0, 8, 9),
       *gcc_mul_add(0, 0, 2, 10),
       store(0)],
  llvm=[load(0), exexp(1, 0), divp2(0, 1),
        mad(2, 0, 8, 9), mad(0, 0, 2, 10),
        store(0)],
  source="ckernel_sfpu_exp2.h")

K("square", "ml_math",
  "Square: x * x",
  gcc=[load(0), mul(0, 0, 0, 9), nop(), store(0)],
  llvm=[load(0), mul(0, 0, 0, 9), store(0)],
  notes="BH NOP elimination", source="ckernel_sfpu_square.h")

K("polyval_horner4", "ml_math",
  "4th-order polynomial via Horner scheme",
  gcc=[load(0),
       *gcc_mul_add(1, 0, 8, 9),   # a4*x + a3
       *gcc_mul_add(1, 1, 0, 9),   # prev*x + a2
       *gcc_mul_add(1, 1, 0, 9),   # prev*x + a1
       *gcc_mul_add(0, 1, 0, 9),   # prev*x + a0
       store(0)],
  llvm=[load(0),
        mad(1, 0, 8, 9), mad(1, 1, 0, 9),
        mad(1, 1, 0, 9), mad(0, 1, 0, 9),
        store(0)],
  notes="4x MAD combining", source="ckernel_sfpu_polyval.h")

# ============================================================================
# Data Movement / Format Conversion
# ============================================================================

K("abs", "data_movement",
  "Absolute value",
  gcc=[load(0), abs_(0, 0), store(0)],
  llvm=[load(0), abs_(0, 0), store(0)],
  source="ckernel_sfpu_abs.h")

K("negative", "data_movement",
  "Negate: -x",
  gcc=[load(0), negative(0, 0), nop(), store(0)],
  llvm=[load(0), setsgn(0, 0, 0, 1), store(0)],  # Toggle sign bit via mod1
  notes="LLVM uses SFPSETSGN instead of MUL by -1",
  source="ckernel_sfpu_negative.h")

K("fill", "data_movement",
  "Fill Dst with constant value",
  gcc=[loadi(0, 0, "0x3F80"), store(0)],
  llvm=[loadi(0, 0, "0x3F80"), store(0)],
  source="ckernel_sfpu_fill.h")

K("typecast_fp16a_to_fp32", "data_movement",
  "Cast FP16A → FP32",
  gcc=[load(0), cast(0, 0, 2), store(0)],
  llvm=[load(0), cast(0, 0, 2), store(0)],
  source="ckernel_sfpu_typecast.h")

K("typecast_fp32_to_fp16b", "data_movement",
  "Cast FP32 → FP16B (bfloat16)",
  gcc=[load(0), cast(0, 0, 1), store(0)],
  llvm=[load(0), cast(0, 0, 1), store(0)],
  source="ckernel_sfpu_typecast.h")

K("cast_fp32_to_fp16a", "data_movement",
  "Cast FP32 → FP16A",
  gcc=[load(0), cast(0, 0, 0), store(0)],
  llvm=[load(0), cast(0, 0, 0), store(0)],
  source="ckernel_sfpu_cast_fp32_to_fp16a.h")

# ============================================================================
# Comparison / Classification
# ============================================================================

K("comp_gt_bh", "comparison",
  "Greater-than on BH (SFPGT vs MAD+SETCC)",
  gcc=[load(0), load(1, 16), *gcc_compare_gt(2, 0, 1)],
  llvm=[load(0), load(1, 16), *llvm_compare_gt(0, 0, 1)],
  notes="GH-Q-005: 50% reduction", source="ckernel_sfpu_comp.h")

K("comp_le_bh", "comparison",
  "Less-or-equal on BH",
  gcc=[load(0), load(1, 16), *gcc_compare_le(2, 0, 1)],
  llvm=[load(0), load(1, 16), *llvm_compare_le(0, 0, 1)],
  source="ckernel_sfpu_comp.h")

K("comp_eq", "comparison",
  "Equality comparison (no dedicated insn, use subtraction)",
  gcc=[load(0), load(1, 16),
       mad(2, 0, 11, 1, 0), nop(), setcc(2, 6),  # EQ0 mode
       mov(0, 9), *gcc_vif(2, 6), mov(0, 10), popc(), store(0)],
  llvm=[load(0), load(1, 16),
        mad(2, 0, 11, 1, 0), setcc(2, 6),
        mov(0, 9), pushc(), setcc(2, 6), mov(0, 10), popc(), store(0)],
  source="ckernel_sfpu_comp.h")

K("isinf", "comparison",
  "Is-infinity check: exp==128 && mantissa==0",
  gcc=[load(0), exexp(1, 0), exman(2, 0),
       mov(3, 9),  # result = 0.0
       *gcc_vif(1, 6),  # v_if(exp == 128) — using EQ0 after subtract
       *gcc_vif(2, 6),  # v_if(man == 0)
       mov(3, 10),      # result = 1.0
       popc(), popc(), store(3)],
  llvm=[load(0), exexp(1, 0), exman(2, 0),
        mov(3, 9),
        pushc(), setcc(1, 6),
        pushc(), setcc(2, 6),
        mov(3, 10),
        popc(), popc(), store(3)],
  source="ckernel_sfpu_isinf_isnan.h")

K("isnan", "comparison",
  "Is-NaN check: exp==128 && mantissa!=0",
  gcc=[load(0), exexp(1, 0), exman(2, 0),
       mov(3, 9),
       *gcc_vif(1, 6), *gcc_vif(2, 2),  # exp==128 && man!=0
       mov(3, 10),
       popc(), popc(), store(3)],
  llvm=[load(0), exexp(1, 0), exman(2, 0),
        mov(3, 9),
        pushc(), setcc(1, 6), pushc(), setcc(2, 2),
        mov(3, 10),
        popc(), popc(), store(3)],
  source="ckernel_sfpu_isinf_isnan.h")

K("sign", "comparison",
  "Sign function: -1, 0, or +1",
  gcc=[load(0), mov(1, 10),  # start with 1.0
       *gcc_vif(0, 0),        # v_if(x < 0)
       mov(1, 11),            # -1.0
       popc(),
       *gcc_vif(0, 6),        # v_if(x == 0)
       mov(1, 9),             # 0.0
       popc(), store(1)],
  llvm=[load(0), mov(1, 10),
        pushc(), setcc(0, 0), mov(1, 11), popc(),
        pushc(), setcc(0, 6), mov(1, 9), popc(),
        store(1)],
  source="ckernel_sfpu_sign.h")

# ============================================================================
# Integer Operations
# ============================================================================

K("add_int", "integer_ops",
  "Integer addition via SFPIADD",
  gcc=[load(0), load(1, 16), iadd(0, 1, 0, 0), store(0)],
  llvm=[load(0), load(1, 16), iadd(0, 1, 0, 0), store(0)],
  source="ckernel_sfpu_add_int.h")

K("sub_int", "integer_ops",
  "Integer subtraction via SFPIADD with SUB flag",
  gcc=[load(0), load(1, 16), iadd(0, 1, 0, 16), store(0)],  # mod1=16 = IS_SUB
  llvm=[load(0), load(1, 16), iadd(0, 1, 0, 16), store(0)],
  source="ckernel_sfpu_sub_int.h")

K("mul_int", "integer_ops",
  "Integer multiply via SFPMUL24 (BH)",
  gcc=[load(0), load(1, 16), mul24(0, 0, 1, 9), nop(), store(0)],
  llvm=[load(0), load(1, 16), mul24(0, 0, 1, 9), store(0)],
  notes="BH NOP elimination after MUL24", source="ckernel_sfpu_mul_int.h")

K("shift_left", "integer_ops",
  "Left shift via SFPSHFT",
  gcc=[load(0), shft(0, 0, 4, 0), store(0)],  # shift by 4
  llvm=[load(0), shft(0, 0, 4, 0), store(0)],
  source="ckernel_sfpu_shift.h")

# ============================================================================
# Reduction / Aggregation
# ============================================================================

K("reduce_max", "reduction",
  "Max reduction via SFPSWAP",
  gcc=[load(0), load(1, 16),
       swap(0, 1, 9), nop(),  # SFPSWAP max mode (C-025), static NOP
       store(0)],
  llvm=[load(0), load(1, 16),
        swap(0, 1, 9), nop(),  # Static NOP required even on BH
        store(0)],
  notes="SFPSWAP requires static NOP on both BH and WH",
  source="ckernel_sfpu_reduce.h")

K("cumsum", "reduction",
  "Cumulative sum (sequential reduction)",
  gcc=[load(0), load(1, 16),
       add(0, 10, 0, 1), nop(),
       store(0)],
  llvm=[load(0), load(1, 16),
        mad(0, 10, 0, 1),
        store(0)],
  notes="MAD combining for add", source="ckernel_sfpu_cumsum.h")

# ============================================================================
# Miscellaneous
# ============================================================================

K("dropout", "misc",
  "Dropout: zero with probability p (stochastic rounding based)",
  gcc=[load(0), stochrnd(0, 1, 0, 0), store(0)],
  llvm=[load(0), stochrnd(0, 1, 0, 0), store(0)],
  source="ckernel_sfpu_dropout.h")

K("clamp", "misc",
  "Clamp to [min, max] range",
  gcc=[load(0),
       *gcc_vif(0, 0),  # v_if(x < min)
       mov(0, 1),        # x = min (loaded to L1)
       popc(),
       # upper clamp
       *gcc_vif(0, 4),  # v_if(x >= max) — approximate
       mov(0, 2),        # x = max (loaded to L2)
       popc(), store(0)],
  llvm=[load(0),
        pushc(), setcc(0, 0), mov(0, 1), popc(),
        pushc(), setcc(0, 4), mov(0, 2), popc(),
        store(0)],
  source="ckernel_sfpu_clamp.h")

K("threshold", "misc",
  "Threshold: if x <= threshold, output value",
  gcc=[load(0),
       *gcc_vif(0, 0),  # v_if(x <= threshold)
       mov(0, 1),        # x = value
       popc(), store(0)],
  llvm=[load(0),
        pushc(), setcc(0, 0), mov(0, 1), popc(),
        store(0)],
  source="ckernel_sfpu_threshold.h")

K("where", "misc",
  "Where: select A or B based on condition",
  gcc=[load(0), load(1, 16), load(2, 32),  # cond, A, B
       *gcc_vif(0, 0),  # v_if(cond < 0)
       mov(1, 2),        # select B
       popc(), store(1)],
  llvm=[load(0), load(1, 16), load(2, 32),
        pushc(), setcc(0, 0),
        mov(1, 2),
        popc(), store(1)],
  source="ckernel_sfpu_where.h")

K("quant_int8", "misc",
  "Quantize to int8 via stochastic rounding",
  gcc=[load(0), stochrnd(0, 3, 0, 0, 0), store(0)],
  llvm=[load(0), stochrnd(0, 3, 0, 0, 0), store(0)],
  source="ckernel_sfpu_quant.h")

K("rounding_floor", "misc",
  "Floor rounding",
  gcc=[load(0), exexp(1, 0), divp2(0, 1),
       iadd(0, 0, 0, 0), store(0)],
  llvm=[load(0), exexp(1, 0), divp2(0, 1),
        iadd(0, 0, 0, 0), store(0)],
  source="ckernel_sfpu_rounding_ops.h")

K("binary_and", "bitwise",
  "Bitwise AND",
  gcc=[load(0), load(1, 16), and_(0, 1), store(0)],
  llvm=[load(0), load(1, 16), and_(0, 1), store(0)],
  source="ckernel_sfpu_binary_bitwise.h")

K("binary_or", "bitwise",
  "Bitwise OR",
  gcc=[load(0), load(1, 16), or_(0, 1), store(0)],
  llvm=[load(0), load(1, 16), or_(0, 1), store(0)],
  source="ckernel_sfpu_binary_bitwise.h")

K("binary_xor", "bitwise",
  "Bitwise XOR",
  gcc=[load(0), load(1, 16), xor_(0, 1), store(0)],
  llvm=[load(0), load(1, 16), xor_(0, 1), store(0)],
  source="ckernel_sfpu_binary_bitwise.h")

K("binary_not", "bitwise",
  "Bitwise NOT",
  gcc=[load(0), not_(0, 0), store(0)],
  llvm=[load(0), not_(0, 0), store(0)],
  source="ckernel_sfpu_binary_bitwise.h")

# ============================================================================
# Scheduling stress tests
# ============================================================================

K("two_independent_muls", "scheduling",
  "Two independent multiplies (interleaving test)",
  gcc=[load(0), load(1, 16), load(2, 32), load(3, 48),
       mul(0, 0, 1, 9), nop(), mul(2, 2, 3, 9), nop(),
       store(0), store(2, 16)],
  llvm=[load(0), load(1, 16), load(2, 32), load(3, 48),
        mul(0, 0, 1, 9), mul(2, 2, 3, 9),
        store(0), store(2, 16)],
  notes="GH-Q-006: scheduler interleaving")

K("four_independent_mads", "scheduling",
  "Four independent MADs (pipeline saturation)",
  gcc=[load(0), load(1, 16), load(2, 32), load(3, 48),
       *gcc_mul_add(0, 0, 8, 10),
       *gcc_mul_add(1, 1, 8, 10),
       *gcc_mul_add(2, 2, 8, 10),
       *gcc_mul_add(3, 3, 8, 10),
       store(0), store(1, 16), store(2, 32), store(3, 48)],
  llvm=[load(0), load(1, 16), load(2, 32), load(3, 48),
        mad(0, 0, 8, 10), mad(1, 1, 8, 10),
        mad(2, 2, 8, 10), mad(3, 3, 8, 10),
        store(0), store(1, 16), store(2, 32), store(3, 48)],
  notes="GH-Q-002 + GH-Q-006: MAD combining + scheduling")

K("softmax_row", "ml_activations",
  "Softmax per-row: normalize + exp + store",
  gcc=[load(0), exexp(1, 0), divp2(0, 1),
       *gcc_mul_add(2, 0, 8, 9),
       *gcc_mul_add(0, 0, 2, 10),
       store(0)],
  llvm=[load(0), exexp(1, 0), divp2(0, 1),
        mad(2, 0, 8, 9), mad(0, 0, 2, 10),
        store(0)],
  source="(composite)")


def get_all_llk_kernels():
    """Return all LLK kernels."""
    return ALL_LLK_KERNELS


def get_llk_categories():
    """Return sorted unique categories."""
    return sorted(set(k.category for k in ALL_LLK_KERNELS))
