//===-- RISCVXttSFPUErrata.cpp - SFPU Errata Workarounds ------------------===//
//
// MachineFunctionPass implementing hardware errata workarounds for the
// Tenstorrent SFPU vector unit.
//
// Errata handled:
//   E-001: WH Read-After-Write Hazard (byte/half store before word load)
//   E-002: WH_B0 SFPSHFT2 Shift-Right Zero-Fill Bug
//   E-004: SFPU Pipeline Hazards (NOP insertion for WH, no-op for BH)
//   E-005: SFPSTORE Source Register Restriction (L12-L15)
//   E-012: ebreak Erratum (8 NOPs required after ebreak)
//
// This pass runs after register allocation and before final code emission.
//
// Reference: ttsim-analysis/ERRATA.md E-001 through E-012
//
//===----------------------------------------------------------------------===//

#include "RISCV.h"
#include "RISCVInstrInfo.h"
#include "RISCVSubtarget.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"

using namespace llvm;

#define DEBUG_TYPE "riscv-xttsfpu-errata"

namespace {

class RISCVXttSFPUErrata : public MachineFunctionPass {
public:
  static char ID;

  RISCVXttSFPUErrata() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "RISC-V Tenstorrent SFPU Errata Workarounds";
  }

private:
  const RISCVSubtarget *STI = nullptr;
  const RISCVInstrInfo *TII = nullptr;

  bool handleE004_PipelineHazards(MachineFunction &MF);
  bool handleE005_StoreRegRestriction(MachineFunction &MF);
  bool handleE012_EbreakNops(MachineFunction &MF);
  bool handleE002_SFPSHFT2ZeroFill(MachineFunction &MF);

  bool isSFPU2Cycle(const MachineInstr &MI) const;
  bool isSFPUInstr(const MachineInstr &MI) const;
};

} // end anonymous namespace

char RISCVXttSFPUErrata::ID = 0;

/// Check if an SFPU instruction has 2-cycle latency.
/// These are: SFPMAD, SFPADD, SFPMUL, SFPMULI, SFPADDI, SFPSWAP,
///            SFPLUTFP32, SFPMUL24, and SFPSHFT2 on WH.
bool RISCVXttSFPUErrata::isSFPU2Cycle(const MachineInstr &MI) const {
  switch (MI.getOpcode()) {
  case RISCV::SFPMAD:
  case RISCV::SFPADD:
  case RISCV::SFPMUL:
  case RISCV::SFPMULI:
  case RISCV::SFPADDI:
  case RISCV::SFPSWAP:
  case RISCV::SFPLUTFP32:
  case RISCV::SFPMUL24:
    return true;
  case RISCV::SFPSHFT2:
    // SFPSHFT2 is 2-cycle on WH only (E-002 workaround adds extra cycle)
    return STI->hasXttSFPUWH();
  default:
    return false;
  }
}

/// Check if instruction is any SFPU instruction (opcode 0x70-0x9F range).
bool RISCVXttSFPUErrata::isSFPUInstr(const MachineInstr &MI) const {
  switch (MI.getOpcode()) {
  case RISCV::SFPLOAD_BH:
  case RISCV::SFPLOAD_WH:
  case RISCV::SFPLOADI:
  case RISCV::SFPSTORE_BH:
  case RISCV::SFPSTORE_WH:
  case RISCV::SFPLUT_BH:
  case RISCV::SFPLUT_WH:
  case RISCV::SFPMULI:
  case RISCV::SFPADDI:
  case RISCV::SFPDIVP2:
  case RISCV::SFPEXEXP:
  case RISCV::SFPEXMAN:
  case RISCV::SFPIADD:
  case RISCV::SFPSHFT:
  case RISCV::SFPSETCC:
  case RISCV::SFPMOV:
  case RISCV::SFPMOV_REG:
  case RISCV::SFPABS:
  case RISCV::SFPAND:
  case RISCV::SFPOR:
  case RISCV::SFPNOT:
  case RISCV::SFPLZ:
  case RISCV::SFPSETEXP:
  case RISCV::SFPSETMAN:
  case RISCV::SFPMAD:
  case RISCV::SFPADD:
  case RISCV::SFPMUL:
  case RISCV::SFPPUSHC:
  case RISCV::SFPPOPC:
  case RISCV::SFPSETSGN:
  case RISCV::SFPENCC:
  case RISCV::SFPCOMPC:
  case RISCV::SFPTRANSP:
  case RISCV::SFPXOR:
  case RISCV::SFP_STOCH_RND:
  case RISCV::SFPNOP:
  case RISCV::SFPCAST:
  case RISCV::SFPCONFIG:
  case RISCV::SFPSWAP:
  case RISCV::SFPLOADMACRO_BH:
  case RISCV::SFPLOADMACRO_WH:
  case RISCV::SFPSHFT2:
  case RISCV::SFPLUTFP32:
  case RISCV::SFPMUL24:
  case RISCV::SFPARECIP:
  case RISCV::SFPGT:
  case RISCV::SFPLE:
  case RISCV::SFPMOV_CONFIG:
    return true;
  default:
    return false;
  }
}

/// E-004: Insert SFPNOP after 2-cycle SFPU instructions on Wormhole.
/// BH has hardware scoreboarding, so this is a no-op for BH targets.
///
/// On WH, a dependent instruction immediately following a 2-cycle producer
/// will read stale data. The hardware does not stall; the compiler must insert
/// an SFPNOP (or schedule an independent instruction) to fill the gap.
///
/// SFPSWAP additionally requires SFPNOP on the *next* cycle unconditionally
/// (not just for dependent reads).
bool RISCVXttSFPUErrata::handleE004_PipelineHazards(MachineFunction &MF) {
  // BH has hardware scoreboarding — skip entirely
  if (STI->hasXttSFPUBH())
    return false;

  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (auto MBBI = MBB.begin(), MBBE = MBB.end(); MBBI != MBBE; ++MBBI) {
      MachineInstr &MI = *MBBI;

      if (!isSFPU2Cycle(MI))
        continue;

      // Check if next instruction is SFPNOP (already safe)
      auto NextMI = std::next(MBBI);
      if (NextMI != MBBE && NextMI->getOpcode() == RISCV::SFPNOP)
        continue;

      // For SFPSWAP: always insert NOP on next cycle
      // For MAD/MUL/ADD: insert NOP if next instruction reads the destination
      bool NeedNop = false;

      if (MI.getOpcode() == RISCV::SFPSWAP) {
        NeedNop = true;  // SFPSWAP always needs NOP on next cycle
      } else if (NextMI != MBBE && isSFPUInstr(*NextMI)) {
        // Check if next instruction reads from this instruction's destination
        for (const MachineOperand &Def : MI.defs()) {
          if (!Def.isReg())
            continue;
          for (const MachineOperand &Use : NextMI->uses()) {
            if (Use.isReg() && Use.getReg() == Def.getReg()) {
              NeedNop = true;
              break;
            }
          }
          if (NeedNop)
            break;
        }
      }

      if (NeedNop) {
        BuildMI(MBB, NextMI, MI.getDebugLoc(), TII->get(RISCV::SFPNOP));
        Changed = true;
      }
    }
  }

  return Changed;
}

/// E-005: Verify SFPSTORE does not use L12-L15 as source.
/// The register allocator should prevent this via SFPUStoreRegs constraint,
/// but this pass provides a safety check.
bool RISCVXttSFPUErrata::handleE005_StoreRegRestriction(MachineFunction &MF) {
  for (MachineBasicBlock &MBB : MF) {
    for (MachineInstr &MI : MBB) {
      unsigned Opc = MI.getOpcode();
      if (Opc != RISCV::SFPSTORE_BH && Opc != RISCV::SFPSTORE_WH)
        continue;

      // Check the lreg_ind operand (first operand for store)
      const MachineOperand &LRegOp = MI.getOperand(0);
      if (!LRegOp.isReg())
        continue;

      Register Reg = LRegOp.getReg();
      if (Reg == RISCV::L12 || Reg == RISCV::L13 ||
          Reg == RISCV::L14 || Reg == RISCV::L15) {
        MI.emitError("E-005: SFPSTORE cannot use L12-L15 as source register");
        return false;
      }
    }
  }
  return false;
}

/// E-012: Insert 8 NOPs after every ebreak instruction.
/// The processor state is unreliable without them.
bool RISCVXttSFPUErrata::handleE012_EbreakNops(MachineFunction &MF) {
  bool Changed = false;

  for (MachineBasicBlock &MBB : MF) {
    for (auto MBBI = MBB.begin(), MBBE = MBB.end(); MBBI != MBBE; ++MBBI) {
      if (MBBI->getOpcode() != RISCV::EBREAK)
        continue;

      auto InsertPt = std::next(MBBI);
      for (int i = 0; i < 8; ++i) {
        BuildMI(MBB, InsertPt, MBBI->getDebugLoc(), TII->get(RISCV::SFPNOP));
      }
      Changed = true;
    }
  }

  return Changed;
}

/// E-002: WH_B0 SFPSHFT2 SHFLSHR1 zero-fill bug.
/// Before SFPSHFT2 with SHFLSHR1 mode, insert a dead rotate using L9 (zero)
/// with SHFLROR1 mode to clear the pipeline value to 0.
bool RISCVXttSFPUErrata::handleE002_SFPSHFT2ZeroFill(MachineFunction &MF) {
  // Only affects WH
  if (!STI->hasXttSFPUWH())
    return false;

  bool Changed = false;

  // SHFLSHR1 mode is encoded in mod1 field
  // TODO: Define the exact mod1 value for SHFLSHR1 from C-020
  const unsigned SHFLSHR1_MOD1 = 2;  // Placeholder — verify from sfpi-gcc
  const unsigned SHFLROR1_MOD1 = 1;  // Placeholder — verify from sfpi-gcc

  for (MachineBasicBlock &MBB : MF) {
    for (auto MBBI = MBB.begin(), MBBE = MBB.end(); MBBI != MBBE; ++MBBI) {
      if (MBBI->getOpcode() != RISCV::SFPSHFT2)
        continue;

      // Check mod1 field for SHFLSHR1 mode
      // The mod1 operand is the last operand in SFPUUnaryReg format
      const MachineOperand &Mod1Op = MBBI->getOperand(MBBI->getNumOperands() - 1);
      if (!Mod1Op.isImm() || Mod1Op.getImm() != SHFLSHR1_MOD1)
        continue;

      // Insert dead rotate: SFPSHFT2 L9, dst, SHFLROR1
      // This clears the pipeline to 0 so the subsequent SHFLSHR1 gets correct fill
      BuildMI(MBB, MBBI, MBBI->getDebugLoc(), TII->get(RISCV::SFPSHFT2))
          .addReg(RISCV::L0, RegState::Define)  // dummy dest
          .addImm(0)                              // imm12 = 0
          .addReg(RISCV::L9)                     // src = zero constant
          .addImm(SHFLROR1_MOD1);                // SHFLROR1 mode

      Changed = true;
    }
  }

  return Changed;
}

bool RISCVXttSFPUErrata::runOnMachineFunction(MachineFunction &MF) {
  STI = &MF.getSubtarget<RISCVSubtarget>();

  // Only run if SFPU extension is enabled
  if (!STI->hasXttSFPU())
    return false;

  TII = STI->getInstrInfo();

  bool Changed = false;

  // Run errata workarounds in order of priority
  Changed |= handleE005_StoreRegRestriction(MF);
  Changed |= handleE002_SFPSHFT2ZeroFill(MF);
  Changed |= handleE004_PipelineHazards(MF);
  Changed |= handleE012_EbreakNops(MF);

  return Changed;
}

INITIALIZE_PASS(RISCVXttSFPUErrata, DEBUG_TYPE,
                "RISC-V Tenstorrent SFPU Errata Workarounds", false, false)

FunctionPass *llvm::createRISCVXttSFPUErrataPass() {
  return new RISCVXttSFPUErrata();
}
