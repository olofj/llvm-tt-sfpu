#!/usr/bin/env python3
"""
generate_test_vectors.py — Generate binary test vectors for ttsim validation.

Produces pairs of (instruction_word, expected_behavior) that can be used to:
1. Validate LLVM MC-layer encoding byte-for-byte
2. Feed instruction words to ttsim for functional verification
3. Compare LLVM codegen output against GCC-compiled kernels

Each test vector is a 32-bit instruction word (with bits[1:0]=0b11) plus
metadata about what the instruction should do.
"""

import json
import struct
import sys

def tt_op(opcode, params):
    return ((opcode << 24) + params) | 0x03

# GCC-exact formulas
def unary(opc, imm12, c, dest, mod1):
    return tt_op(opc, (imm12 << 12) | (c << 8) | (dest << 4) | mod1)

def three_op(opc, a, b, c, dest, mod1):
    return tt_op(opc, (a << 16) | (b << 12) | (c << 8) | (dest << 4) | mod1)

def load_bh(opc, lreg, mod0, am, addr):
    return tt_op(opc, (lreg << 20) | (mod0 << 16) | (am << 13) | addr)

def loadi(lreg, mod0, imm16):
    return tt_op(0x71, (lreg << 20) | (mod0 << 16) | imm16)

def imm16_fmt(opc, imm, dest, mod1):
    return tt_op(opc, (imm << 8) | (dest << 4) | mod1)

def lut_fmt(lreg, mod0, dra):
    return tt_op(0x73, (lreg << 20) | (mod0 << 16) | dra)

def stoch_rnd(rnd, imm5, sb, sc, dest, mod1):
    return tt_op(0x8e, (rnd << 21) | (imm5 << 16) | (sb << 12) | (sc << 8) | (dest << 4) | mod1)

def loadmacro_bh(lreg, mod0, am, addr):
    return tt_op(0x93, (lreg << 20) | (mod0 << 16) | (am << 14) | addr)

# ============================================================================
# Test vector generation
# ============================================================================

vectors = []

def add_vector(name, word, category, description, operands=None):
    vectors.append({
        "name": name,
        "word": f"0x{word:08x}",
        "word_int": word,
        "category": category,
        "description": description,
        "operands": operands or {},
        "opcode": f"0x{(word >> 24) & 0xFF:02x}",
    })

# --- Softmax kernel test sequence ---
# A typical softmax SFPU kernel does:
# 1. Load input from Dst
# 2. Extract exponent, find max
# 3. Subtract max (normalization)
# 4. Exp approximation (Horner series)
# 5. Reciprocal of sum
# 6. Multiply each element by reciprocal
# 7. Store result to Dst

# Step 1: Load from Dst row 0
add_vector("softmax_load", load_bh(0x70, 0, 0, 0, 0),
    "softmax", "Load Dst[0] to L0",
    {"lreg": 0, "mod0": 0, "addr_mode": 0, "addr": 0})

# Step 2: Extract exponent for max-finding
add_vector("softmax_exexp", unary(0x77, 0, 0, 1, 0),
    "softmax", "Extract exponent of L0 to L1 (DEBIAS mode)",
    {"imm12": 0, "lreg_c": 0, "lreg_dest": 1, "mod1": 0})

# Step 3: Normalize by subtracting max exponent
add_vector("softmax_divp2", unary(0x76, 0, 1, 0, 0),
    "softmax", "Divide L0 by 2^L1 (subtract exponent)",
    {"imm12": 0, "lreg_c": 1, "lreg_dest": 0, "mod1": 0})

# Step 4: exp via Horner: tmp = val * 0.8373 + 0.863
add_vector("softmax_mad1", three_op(0x84, 0, 8, 9, 2, 0),
    "softmax", "L2 = L0 * L8(0.8373) + L9(0.0) [Horner step 1]",
    {"src_a": 0, "src_b": 8, "src_c": 9, "dest": 2, "mod1": 0})

# Step 4b: val = val * tmp + 1.0
add_vector("softmax_mad2", three_op(0x84, 0, 2, 10, 0, 0),
    "softmax", "L0 = L0 * L2 + L10(1.0) [Horner step 2]",
    {"src_a": 0, "src_b": 2, "src_c": 10, "dest": 0, "mod1": 0})

# Step 5: Store result to Dst
add_vector("softmax_store", load_bh(0x72, 0, 0, 0, 0),
    "softmax", "Store L0 to Dst[0]",
    {"lreg": 0, "mod0": 0, "addr_mode": 0, "addr": 0})

# --- SFPNOP ---
add_vector("nop", tt_op(0x8f, 0), "control", "Pipeline NOP")

# --- Predication sequence: v_if(x < 0) ---
add_vector("pushc", unary(0x87, 0, 0, 0, 0),
    "predication", "Push CC stack (v_if begin)")

add_vector("setcc_lt0", unary(0x7B, 0, 0, 0, 0),
    "predication", "Set CC: L0 < 0 (LREG_LT0 mode)",
    {"mod1": 0})

add_vector("compc", unary(0x8B, 0, 0, 0, 0),
    "predication", "Complement CC (v_else)")

add_vector("popc", unary(0x88, 0, 0, 0, 0),
    "predication", "Pop CC stack (v_endif)")

# --- SFPLOADI coefficient loading (from tanh kernel) ---
add_vector("loadi_coeff0", loadi(0, 0, 0x1DFF),
    "tanh", "Load tanh coeff0 (0x1DFF = 0.90625*x) to L0",
    {"lreg": 0, "mod0": 0, "imm16": 0x1DFF})

add_vector("loadi_coeff1", loadi(1, 0, 0x481A),
    "tanh", "Load tanh coeff1 (0x481A = 0.09375*x + 0.8125) to L1",
    {"lreg": 1, "mod0": 0, "imm16": 0x481A})

add_vector("loadi_coeff2", loadi(2, 0, 0xFF00),
    "tanh", "Load tanh coeff2 (0xFF00 = 1.0) to L2",
    {"lreg": 2, "mod0": 0, "imm16": 0xFF00})

# --- SFPLUT (tanh via LUT) ---
add_vector("lut_tanh", lut_fmt(3, 0, 0),
    "tanh", "LUT lookup: L3 = tanh_lut(Dst[0], L0, L1, L2)")

# --- BH-only: SFPGT comparison ---
add_vector("sfpgt", unary(0x9A, 0, 1, 0, 0),
    "comparison_bh", "SFPGT: set CC if L0 > L1",
    {"lreg_c": 1, "lreg_dest": 0, "mod1": 0})

# --- SFPMUL24 (BH integer multiply) ---
add_vector("sfpmul24", three_op(0x96, 1, 2, 9, 0, 0),
    "integer_bh", "SFPMUL24: L0 = L1 * L2 (23-bit integer, src_c=L9=zero)")

# --- SFPCAST (format conversion) ---
add_vector("cast_fp16a_to_fp32", unary(0x90, 0, 1, 0, 2),
    "cast", "Cast L1 FP16A → FP32, store in L0",
    {"mod1": 2})

# --- Stochastic rounding ---
add_vector("stochrnd_fp32_to_fp16b", stoch_rnd(1, 0, 0, 0, 3, 0),
    "rounding", "Stochastic round L3 FP32 → FP16B",
    {"rnd_mode": 1, "imm5": 0, "src_b": 0, "src_c": 0, "dest": 3})

# --- SFPSWAP min/max ---
add_vector("swap_min", unary(0x92, 0, 1, 0, 1),
    "swap", "SFPSWAP min: L0 = min(L0, L1), L1 = max",
    {"mod1": 1})

add_vector("swap_max", unary(0x92, 0, 1, 0, 9),
    "swap", "SFPSWAP max: L0 = max(L0, L1), L1 = min (C-025)",
    {"mod1": 9})

# --- SFPCONFIG (write to L11) ---
add_vector("config_l11", imm16_fmt(0x91, 0x3F80, 11, 0),
    "config", "SFPCONFIG: write 0x3F80 to L11 (VD=11)",
    {"imm16": 0x3F80, "config_dest": 11})

# ============================================================================
# Output
# ============================================================================

# JSON output
json_path = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdout"
with open(json_path, "w") as f:
    json.dump({
        "description": "SFPU instruction test vectors for ttsim validation",
        "source": "Generated from GCC sfpu-ops-bh.h encoding formulas",
        "total_vectors": len(vectors),
        "vectors": vectors
    }, f, indent=2)

# Summary
print(f"Generated {len(vectors)} test vectors", file=sys.stderr)
categories = {}
for v in vectors:
    categories[v["category"]] = categories.get(v["category"], 0) + 1
for cat, count in sorted(categories.items()):
    print(f"  {cat}: {count}", file=sys.stderr)

# Also generate a raw binary file (instruction words only, little-endian)
bin_path = json_path.replace(".json", ".bin") if json_path.endswith(".json") else None
if bin_path:
    with open(bin_path, "wb") as f:
        for v in vectors:
            f.write(struct.pack("<I", v["word_int"]))
    print(f"Binary output: {bin_path} ({len(vectors) * 4} bytes)", file=sys.stderr)
