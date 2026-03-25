//===-- RISCVXttSFPUISelPatterns.td - ISel DAG Patterns -----*- tablegen -*-===//
//
// ISel DAG patterns for the Tenstorrent SFPU extension.
// These patterns enable the DAGCombiner and ISel to:
// 1. Lower intrinsics to specific SFPU instructions
// 2. Combine sequences (e.g., MUL+ADD → MAD)
// 3. Select BH-specific instructions (SFPGT/SFPLE)
// 4. Fold immediates into instruction operands
//
// Reference: ttsim-analysis/ERRATA.md C-009 (BH-only instructions)
//            GCC gimple-rvtt-combine.cc (combining patterns)
//
//===----------------------------------------------------------------------===//

let Predicates = [HasXttSFPU] in {

//===----------------------------------------------------------------------===//
// Intrinsic → Instruction lowering (Phase 3)
//===----------------------------------------------------------------------===//

// SFPMAD: dest = src_a * src_b + src_c
def : Pat<(int_riscv_tt_sfpmad i32:$src_a, i32:$src_b, i32:$src_c, uimm4_sfpu:$mod1),
          (SFPMAD SFPUAllRegs:$src_a, SFPUAllRegs:$src_b,
                  SFPUAllRegs:$src_c, uimm4_sfpu:$mod1)>;

// SFPMUL: dest = src_a * src_b (src_c typically L9=zero)
def : Pat<(int_riscv_tt_sfpmul i32:$src_a, i32:$src_b, i32:$src_c, uimm4_sfpu:$mod1),
          (SFPMUL SFPUAllRegs:$src_a, SFPUAllRegs:$src_b,
                  SFPUAllRegs:$src_c, uimm4_sfpu:$mod1)>;

// SFPADD: dest = src_a * 1.0 + src_b (effectively src_a + src_b)
def : Pat<(int_riscv_tt_sfpadd i32:$src_a, i32:$src_b, i32:$src_c, uimm4_sfpu:$mod1),
          (SFPADD SFPUAllRegs:$src_a, SFPUAllRegs:$src_b,
                  SFPUAllRegs:$src_c, uimm4_sfpu:$mod1)>;

// SFPMOV
def : Pat<(int_riscv_tt_sfpmov i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPMOV uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPNOP
def : Pat<(int_riscv_tt_sfpnop), (SFPNOP)>;

// SFPPUSHC / SFPPOPC / SFPCOMPC
def : Pat<(int_riscv_tt_sfppushc), (SFPPUSHC 0, L0, L0, 0)>;
def : Pat<(int_riscv_tt_sfppopc), (SFPPOPC 0, L0, L0, 0)>;
def : Pat<(int_riscv_tt_sfpcompc), (SFPCOMPC 0, L0, L0, 0)>;

// SFPSETCC
def : Pat<(int_riscv_tt_sfpsetcc i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPSETCC uimm12_sfpu:$imm, SFPUAllRegs:$src, L0, uimm4_sfpu:$mod1)>;

// SFPABS
def : Pat<(int_riscv_tt_sfpabs i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPABS uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPAND / SFPOR / SFPXOR / SFPNOT
def : Pat<(int_riscv_tt_sfpand i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPAND uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpor i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPOR uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpxor i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPXOR uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpnot i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPNOT uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPEXEXP / SFPEXMAN / SFPLZ
def : Pat<(int_riscv_tt_sfpexexp i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPEXEXP uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpexman i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPEXMAN uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfplz i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPLZ uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPIADD / SFPSHFT
def : Pat<(int_riscv_tt_sfpiadd i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPIADD uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpshft i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPSHFT uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPSETEXP / SFPSETMAN / SFPSETSGN / SFPDIVP2
def : Pat<(int_riscv_tt_sfpsetexp i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPSETEXP uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpsetman i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPSETMAN uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpsetsgn i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPSETSGN uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpdivp2 i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPDIVP2 uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPSWAP / SFPSHFT2 / SFPTRANSP
def : Pat<(int_riscv_tt_sfpswap i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPSWAP uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;
def : Pat<(int_riscv_tt_sfpshft2 i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPSHFT2 uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPCAST
def : Pat<(int_riscv_tt_sfpcast i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPCAST uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPLUTFP32
def : Pat<(int_riscv_tt_sfplutfp32 i32:$src, uimm4_sfpu:$mod1),
          (SFPLUTFP32 SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPCONFIG
def : Pat<(int_riscv_tt_sfpconfig uimm16_sfpu:$imm, uimm4_sfpu:$vd, uimm4_sfpu:$mod1),
          (SFPCONFIG uimm16_sfpu:$imm, uimm4_sfpu:$vd, uimm4_sfpu:$mod1)>;

// SFPENCC
def : Pat<(int_riscv_tt_sfpencc uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPENCC uimm12_sfpu:$imm, L0, L0, uimm4_sfpu:$mod1)>;

//===----------------------------------------------------------------------===//
// _lv intrinsic → instruction lowering (Phase 5)
//===----------------------------------------------------------------------===//

def : Pat<(int_riscv_tt_sfpmov_lv i32:$live, i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPMOV_LV SFPURegs:$live, uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

def : Pat<(int_riscv_tt_sfpmad_lv i32:$live, i32:$a, i32:$b, i32:$c, uimm4_sfpu:$mod1),
          (SFPMAD_LV SFPURegs:$live, SFPUAllRegs:$a, SFPUAllRegs:$b,
                     SFPUAllRegs:$c, uimm4_sfpu:$mod1)>;

def : Pat<(int_riscv_tt_sfpmul_lv i32:$live, i32:$a, i32:$b, i32:$c, uimm4_sfpu:$mod1),
          (SFPMUL_LV SFPURegs:$live, SFPUAllRegs:$a, SFPUAllRegs:$b,
                     SFPUAllRegs:$c, uimm4_sfpu:$mod1)>;

def : Pat<(int_riscv_tt_sfpadd_lv i32:$live, i32:$a, i32:$b, i32:$c, uimm4_sfpu:$mod1),
          (SFPADD_LV SFPURegs:$live, SFPUAllRegs:$a, SFPUAllRegs:$b,
                     SFPUAllRegs:$c, uimm4_sfpu:$mod1)>;

def : Pat<(int_riscv_tt_sfpcast_lv i32:$live, i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPCAST_LV SFPURegs:$live, uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

} // Predicates = [HasXttSFPU]

//===----------------------------------------------------------------------===//
// BH-specific ISel patterns (Phase 6 — beating GCC)
//===----------------------------------------------------------------------===//

let Predicates = [HasXttSFPU, HasXttSFPUBH] in {

// SFPGT: direct comparison (GH-Q-005)
// GCC generates: sfpmad + 2x sfpsetcc. We use the dedicated BH instruction.
def : Pat<(int_riscv_tt_sfpgt i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPGT uimm12_sfpu:$imm, SFPUAllRegs:$src, L0, uimm4_sfpu:$mod1)>;

// SFPLE: direct less-or-equal comparison
def : Pat<(int_riscv_tt_sfple i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPLE uimm12_sfpu:$imm, SFPUAllRegs:$src, L0, uimm4_sfpu:$mod1)>;

// SFPARECIP: approximate reciprocal
def : Pat<(int_riscv_tt_sfparecip i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPARECIP uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

// SFPMUL24: 23-bit integer multiply
def : Pat<(int_riscv_tt_sfpmul24 i32:$a, i32:$b, i32:$c, uimm4_sfpu:$mod1),
          (SFPMUL24 SFPUAllRegs:$a, SFPUAllRegs:$b,
                    SFPUAllRegs:$c, uimm4_sfpu:$mod1)>;

// SFPARECIP _lv variant
def : Pat<(int_riscv_tt_sfparecip_lv i32:$live, i32:$src, uimm12_sfpu:$imm, uimm4_sfpu:$mod1),
          (SFPARECIP_LV SFPURegs:$live, uimm12_sfpu:$imm, SFPUAllRegs:$src, uimm4_sfpu:$mod1)>;

} // Predicates = [HasXttSFPU, HasXttSFPUBH]
