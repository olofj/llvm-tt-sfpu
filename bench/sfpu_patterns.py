"""
sfpu_patterns.py — Common SFPU instruction sequence patterns.

Provides building blocks for constructing GCC and LLVM instruction sequences.
Each pattern models what GCC emits for common SFPI code patterns, and what
LLVM would emit with our optimizations.

GCC patterns are based on:
  - rvtt-bh.md assembly templates
  - rtl-rvtt-schedule.cc NOP insertion (dynamic delay on BH)
  - gimple-rvtt-combine.cc (lack of MUL+ADD→MAD in some cases)

LLVM improvements:
  - MAD combining (MUL+ADD→MAD)
  - BH NOP elimination (hardware scoreboard)
  - SFPGT/SFPLE direct use
  - Scheduler interleaving
  - Negated operand folding
"""


def load(reg, addr=0):
    """SFPLOAD from Dst to LReg."""
    return f"SFPLOAD\tL{reg}, 0, 0, {addr}"


def store(reg, addr=0):
    """SFPSTORE from LReg to Dst."""
    return f"SFPSTORE\tL{reg}, 0, 0, {addr}"


def loadi(reg, mod0, imm16):
    """SFPLOADI immediate to LReg."""
    if isinstance(imm16, int):
        imm16 = f"0x{imm16:04X}" if imm16 > 9 else str(imm16)
    return f"SFPLOADI\tL{reg}, {mod0}, {imm16}"


def mov(dest, src, mod1=0):
    return f"SFPMOV\tL{dest}, L{src}, 0, {mod1}"


def mul(dest, a, b, c=9, mod1=0):
    """SFPMUL: dest = a * b (c is usually L9=zero)."""
    return f"SFPMUL\tL{dest}, L{a}, L{b}, L{c}, {mod1}"


def add(dest, a, b, c=9, mod1=0):
    """SFPADD: dest = a*1.0 + b (a is usually L10=one)."""
    return f"SFPADD\tL{dest}, L{a}, L{b}, L{c}, {mod1}"


def mad(dest, a, b, c, mod1=0):
    """SFPMAD: dest = a * b + c."""
    return f"SFPMAD\tL{dest}, L{a}, L{b}, L{c}, {mod1}"


def muli(dest, imm16, mod1=0):
    return f"SFPMULI\tL{dest}, {imm16}, {mod1}"


def addi(dest, imm16, mod1=0):
    return f"SFPADDI\tL{dest}, {imm16}, {mod1}"


def nop():
    return "SFPNOP"


def abs_(dest, src, mod1=0):
    return f"SFPABS\tL{dest}, L{src}, 0, {mod1}"


def setcc(src, mod1=0):
    return f"SFPSETCC\tL0, L{src}, 0, {mod1}"


def pushc():
    return "SFPPUSHC\tL0, L0, 0, 0"


def popc():
    return "SFPPOPC\tL0, L0, 0, 0"


def compc():
    return "SFPCOMPC\tL0, L0, 0, 0"


def exexp(dest, src, mod1=0):
    return f"SFPEXEXP\tL{dest}, L{src}, 0, {mod1}"


def exman(dest, src, mod1=0):
    return f"SFPEXMAN\tL{dest}, L{src}, 0, {mod1}"


def setexp(dest, src, imm=0, mod1=0):
    return f"SFPSETEXP\tL{dest}, L{src}, {imm}, {mod1}"


def setman(dest, src, imm=0, mod1=0):
    return f"SFPSETMAN\tL{dest}, L{src}, {imm}, {mod1}"


def setsgn(dest, src, imm=0, mod1=0):
    return f"SFPSETSGN\tL{dest}, L{src}, {imm}, {mod1}"


def divp2(dest, src, imm=0, mod1=0):
    return f"SFPDIVP2\tL{dest}, L{src}, {imm}, {mod1}"


def iadd(dest, src, imm=0, mod1=0):
    return f"SFPIADD\tL{dest}, L{src}, {imm}, {mod1}"


def shft(dest, src, imm=0, mod1=0):
    return f"SFPSHFT\tL{dest}, L{src}, {imm}, {mod1}"


def not_(dest, src):
    return f"SFPNOT\tL{dest}, L{src}, 0, 0"


def and_(dest, src, imm=0, mod1=0):
    return f"SFPAND\tL{dest}, L{src}, {imm}, {mod1}"


def or_(dest, src, imm=0, mod1=0):
    return f"SFPOR\tL{dest}, L{src}, {imm}, {mod1}"


def xor_(dest, src, imm=0, mod1=0):
    return f"SFPXOR\tL{dest}, L{src}, {imm}, {mod1}"


def lz(dest, src, mod1=0):
    return f"SFPLZ\tL{dest}, L{src}, 0, {mod1}"


def lut(dest, mod0=0):
    return f"SFPLUT\tL{dest}, {mod0}, 0"


def lutfp32(dest, mod1=0):
    return f"SFPLUTFP32\tL{dest}, L0, {mod1}"


def cast(dest, src, mod1=0):
    return f"SFPCAST\tL{dest}, L{src}, 0, {mod1}"


def swap(a, b, mod1=0):
    return f"SFPSWAP\tL{a}, L{b}, 0, {mod1}"


def arecip(dest, src, mod1=0):
    return f"SFPARECIP\tL{dest}, L{src}, {mod1}"


def stochrnd(dest, rnd_mode, src_b=0, src_c=0, imm5=0, mod1=0):
    return f"SFPSTOCHRND\tL{dest}, {rnd_mode}, {imm5}, L{src_b}, L{src_c}, {mod1}"


def config(imm16, vd, mod1=0):
    return f"SFPCONFIG\t{vd}, {imm16}, {mod1}"


def gt(dest, src, mod1=0):
    return f"SFPGT\tL{dest}, L{src}, 0, {mod1}"


def le(dest, src, mod1=0):
    return f"SFPLE\tL{dest}, L{src}, 0, {mod1}"


def mul24(dest, a, b, c=9, mod1=0):
    return f"SFPMUL24\tL{dest}, L{a}, L{b}, L{c}, {mod1}"


def shft2(dest, src, imm=0, mod1=0):
    return f"SFPSHFT2\tL{dest}, L{src}, {imm}, {mod1}"


def transp(dest, src, mod1=0):
    return f"SFPTRANSP\tL{dest}, L{src}, 0, {mod1}"


def negative(dest, src):
    """Negate via multiply by L11(-1.0)."""
    return mul(dest, src, 11, 9, 0)


# ============================================================================
# Composite GCC patterns (what GCC emits for common SFPI idioms)
# ============================================================================

def gcc_mul_add(dest, a, b, c):
    """GCC pattern: MUL + NOP + ADD (no MAD combining)."""
    return [mul(dest, a, b, 9, 0), nop(), add(dest, 10, dest, c, 0)]


def gcc_compare_gt(out, a, b):
    """GCC pattern: MAD + NOP + 2x SETCC (no SFPGT on BH)."""
    return [mad(out, a, 11, b, 0), nop(), setcc(out, 0), setcc(out, 8)]


def gcc_compare_le(out, a, b):
    """GCC pattern: MAD + NOP + SETCC."""
    return [mad(out, a, 11, b, 0), nop(), setcc(out, 0)]


def llvm_compare_gt(out, a, b):
    """LLVM pattern: direct SFPGT (BH only)."""
    return [gt(out, a, 0)]


def llvm_compare_le(out, a, b):
    """LLVM pattern: direct SFPLE (BH only)."""
    return [le(out, a, 0)]


def gcc_vif(cond_reg, cond_mod=0):
    """GCC v_if pattern."""
    return [pushc(), setcc(cond_reg, cond_mod)]


def gcc_velse():
    """GCC v_else pattern."""
    return [popc(), compc(), pushc()]


def gcc_vendif():
    """GCC v_endif pattern."""
    return [popc()]
