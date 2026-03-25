# SFPU Instruction Encoding Reference

Extracted from ttsim-analysis for use by the LLVM backend implementation.

## Encoding Formats (Validated against sfpu-ops-bh.h)

### Standard Unary (18 instructions)
```
[31:24] opcode | [23:12] imm12_math | [11:8] lreg_c | [7:4] lreg_dest | [3:0] instr_mod1
```

### 3-Operand (SFPMAD, SFPADD, SFPMUL)
**CORRECTED**: bits[23:20] are EMPTY, src_a starts at [19:16]
```
[31:24] opcode | [23:20] EMPTY | [19:16] src_a | [15:12] src_b | [11:8] src_c | [7:4] lreg_dest | [3:0] instr_mod1
```
GCC formula: `(src_a << 16) + (src_b << 12) + (src_c << 8) + (dest << 4) + mod1`

### Load/Store BH (SFPLOAD, SFPSTORE only)
```
[31:24] opcode | [23:20] lreg_ind | [19:16] instr_mod0 | [15:13] sfpu_addr_mode(3b) | [12:0] dest_reg_addr(13b)
```

### Load/Store WH (SFPLOAD, SFPSTORE only)
```
[31:24] opcode | [23:20] lreg_ind | [19:16] instr_mod0 | [15:14] sfpu_addr_mode(2b) | [13:0] dest_reg_addr(14b)
```

### SFPLOADI (Load format with imm16, NOT Imm16 format!)
**CORRECTED**: Uses Load header (lreg + mod0) with imm16 at [15:0]
```
[31:24] 0x71 | [23:20] lreg_ind | [19:16] instr_mod0 | [15:0] imm16
```
GCC formula: `(lreg_ind << 20) + (instr_mod0 << 16) + (imm16 << 0)`

### SFPLUT (no addr_mode field!)
**CORRECTED**: dest_reg_addr is 16 bits, no addr_mode
```
[31:24] 0x73 | [23:20] lreg_ind | [19:16] instr_mod0 | [15:0] dest_reg_addr(16b)
```

### SFPLOADMACRO BH (2-bit addr_mode! C-012)
**CORRECTED**: Uses 2-bit addr_mode even on BH (same as WH)
```
[31:24] 0x93 | [23:20] lreg_ind | [19:16] instr_mod0 | [15:14] sfpu_addr_mode(2b) | [13:0] dest_reg_addr(14b)
```

### Immediate-16 (SFPMULI, SFPADDI, SFPCONFIG)
Note: SFPLOADI does NOT use this format.
```
[31:24] opcode | [23:8] imm16_math | [7:4] lreg_dest | [3:0] instr_mod1
```

### Stochastic Rounding (SFP_STOCH_RND)
**CORRECTED**: 3-bit rnd_mode, 5-bit imm, 6 operands (includes src_c)
```
[31:24] 0x8E | [23:21] rnd_mode(3b) | [20:16] imm5(5b) | [15:12] src_b | [11:8] src_c | [7:4] lreg_dest | [3:0] instr_mod1
```
GCC formula: `(rnd_mode << 21) + (imm << 16) + (src_b << 12) + (src_c << 8) + (dest << 4) + mod1`

## Complete Opcode Map

| Opcode | Mnemonic | Format | Latency | Sub-Unit |
|--------|----------|--------|---------|----------|
| 0x70 | SFPLOAD | Load/Store | 1 | load |
| 0x71 | SFPLOADI | Imm16 | 1 | load |
| 0x72 | SFPSTORE | Load/Store | 1 | store |
| 0x73 | SFPLUT | Load/Store | 1 | load |
| 0x74 | SFPMULI | Imm16 | 2 | MAD |
| 0x75 | SFPADDI | Imm16 | 2 | MAD |
| 0x76 | SFPDIVP2 | Unary | 1 | simple |
| 0x77 | SFPEXEXP | Unary | 1 | simple |
| 0x78 | SFPEXMAN | Unary | 1 | simple |
| 0x79 | SFPIADD | Unary | 1 | simple |
| 0x7A | SFPSHFT | Unary | 1 | simple |
| 0x7B | SFPSETCC | Unary | 1 | simple |
| 0x7C | SFPMOV | Unary | 1 | simple |
| 0x7D | SFPABS | Unary | 1 | simple |
| 0x7E | SFPAND | Unary | 1 | simple |
| 0x7F | SFPOR | Unary | 1 | simple |
| 0x80 | SFPNOT | Unary | 1 | simple |
| 0x81 | SFPLZ | Unary | 1 | simple |
| 0x82 | SFPSETEXP | Unary | 1 | simple |
| 0x83 | SFPSETMAN | Unary | 1 | simple |
| 0x84 | SFPMAD | 3Op | 2 | MAD |
| 0x85 | SFPADD | 3Op | 2 | MAD |
| 0x86 | SFPMUL | 3Op | 2 | MAD |
| 0x87 | SFPPUSHC | Unary | 1 | simple |
| 0x88 | SFPPOPC | Unary | 1 | simple |
| 0x89 | SFPSETSGN | Unary | 1 | simple |
| 0x8A | SFPENCC | Unary | 1 | simple |
| 0x8B | SFPCOMPC | Unary | 1 | simple |
| 0x8C | SFPTRANSP | Unary | 1 | simple |
| 0x8D | SFPXOR | Unary | 1 | simple |
| 0x8E | SFP_STOCH_RND | StochRnd | 1 | round |
| 0x8F | SFPNOP | — | 1 | — |
| 0x90 | SFPCAST | Unary | 1 | simple |
| 0x91 | SFPCONFIG | Imm16 | 1 | simple |
| 0x92 | SFPSWAP | Unary | 2 | simple |
| 0x93 | SFPLOADMACRO | Load/Store | 1 | load |
| 0x94 | SFPSHFT2 | Unary | 1-2 | simple |
| 0x95 | SFPLUTFP32 | Special | 2 | MAD |

### BH-Only
| 0x96 | SFPMUL24 | 3Op | 2 | MAD |
| 0x99 | SFPARECIP | Unary | 1 | simple |

## Register File

| Reg | Encoding | Allocatable | Content |
|-----|----------|-------------|---------|
| L0-L7 | 0-7 | Yes | General purpose |
| L8 | 8 | No (read-only) | 0.8373 |
| L9 | 9 | No (read-only) | 0.0 |
| L10 | 10 | No (read-only) | 1.0 |
| L11 | 11 | No (SFPCONFIG) | -1.0 (default) |
| L12 | 12 | No (SFPCONFIG) | 2^-9 (default) |
| L13 | 13 | No (SFPCONFIG) | -0.6749 (default) |
| L14 | 14 | No (SFPCONFIG) | -0.3448 (default) |
| L15 | 15 | No (read-only) | Lane ID (2*i) |
| L16 | 16 | No (special) | SFPLOADMACRO/SFPSTORE only |
