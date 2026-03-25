//===-- RISCVSchedXttSFPU.td - SFPU Scheduling Model -------*- tablegen -*-===//
//
// Scheduling model for the Tenstorrent SFPU (Vector Unit).
// Addresses GH-Q-006: "No Pipeline Model for Instruction Scheduling"
//
// The SFPU has 5 internal sub-units, each with specific latencies.
// At most 1 SFPU instruction can issue per cycle (in-order).
// BH has hardware scoreboarding (no manual NOP insertion needed).
// WH requires software NOP insertion after 2-cycle instructions.
//
// Reference: ttsim-analysis/FUNCTIONAL_UNITS.md Section 3.1
//            ttsim-analysis/ERRATA.md E-004 (pipeline hazards)
//
//===----------------------------------------------------------------------===//

// --- SFPU Sub-Unit Resources ---
// 5 sub-units, each can execute 1 instruction per cycle.

def SFPULoadUnit   : ProcResource<1> { let BufferSize = 0; }
def SFPUSimpleUnit : ProcResource<1> { let BufferSize = 0; }
def SFPUMADUnit    : ProcResource<1> { let BufferSize = 0; }
def SFPURoundUnit  : ProcResource<1> { let BufferSize = 0; }
def SFPUStoreUnit  : ProcResource<1> { let BufferSize = 0; }

// The SFPU accepts at most 1 instruction per cycle total across all sub-units.
def SFPUPort : ProcResGroup<[SFPULoadUnit, SFPUSimpleUnit, SFPUMADUnit,
                              SFPURoundUnit, SFPUStoreUnit]>;

// --- Write Resources (instruction latencies) ---

// 1-cycle simple operations (MOV, logic, comparisons, CC stack, shifts)
def WriteSFPUSimple : SchedWrite;

// 1-cycle load operations (SFPLOAD, SFPLOADI, SFPLUT, SFPLOADMACRO)
def WriteSFPULoad : SchedWrite;

// 1-cycle store operations (SFPSTORE)
def WriteSFPUStore : SchedWrite;

// 1-cycle rounding operations (SFP_STOCH_RND, SFPCAST)
def WriteSFPURound : SchedWrite;

// 2-cycle MAD operations (SFPMAD, SFPADD, SFPMUL, SFPMULI, SFPADDI)
def WriteSFPUMAD : SchedWrite;

// 2-cycle swap operations (SFPSWAP — uses simple unit but 2-cycle latency)
def WriteSFPUSwap : SchedWrite;

// 2-cycle SFPLUTFP32 (uses MAD unit)
def WriteSFPULUTFP32 : SchedWrite;

// 1-2 cycle SFPSHFT2 (1 cycle on BH for most modes, 2 on WH for some)
def WriteSFPUShft2 : SchedWrite;

// SFPNOP — 1 cycle, no resource
def WriteSFPUNop : SchedWrite;

// --- Read Resources ---

def ReadSFPUSrc : SchedRead;

// --- Blackhole Scheduling Model ---
// BH has hardware scoreboarding — stalls are inserted by hardware, not software.

def TensixBHModel : SchedMachineModel {
  let IssueWidth = 1;            // 1 SFPU instruction per cycle (in-order)
  let MicroOpBufferSize = 0;     // In-order execution, no reorder buffer
  let LoadLatency = 2;           // L1 load via SFPLOAD (Dst -> LReg)
  let MispredictPenalty = 5;     // Branch misprediction (RV32 scalar core)
  let CompleteModel = 0;         // Allow instructions without sched info
  let PostRAScheduler = 1;       // Enable post-RA scheduling for SFPU
}

let SchedModel = TensixBHModel in {

  // --- 1-cycle write resources ---

  def : WriteRes<WriteSFPUSimple, [SFPUSimpleUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPULoad, [SFPULoadUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPUStore, [SFPUStoreUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPURound, [SFPURoundUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPUNop, []> {
    let Latency = 1;
  }

  // --- 2-cycle write resources ---

  def : WriteRes<WriteSFPUMAD, [SFPUMADUnit]> {
    let Latency = 2;
    let ReleaseAtCycles = [1];   // Unit free after 1 cycle, result after 2
  }

  def : WriteRes<WriteSFPUSwap, [SFPUSimpleUnit]> {
    let Latency = 2;
    let ReleaseAtCycles = [2];   // SFPSWAP blocks simple unit for 2 cycles
  }

  def : WriteRes<WriteSFPULUTFP32, [SFPUMADUnit]> {
    let Latency = 2;
    let ReleaseAtCycles = [2];   // SFPLUTFP32 uses MAD for 2 cycles
  }

  def : WriteRes<WriteSFPUShft2, [SFPUSimpleUnit]> {
    let Latency = 1;             // 1 cycle on BH (WH model overrides to 2)
    let ReleaseAtCycles = [1];
  }

  // --- Read resources ---
  // Sources are read at issue time (cycle 0).

  def : ReadAdvance<ReadSFPUSrc, 0>;

} // SchedModel = TensixBHModel

// --- Wormhole Scheduling Model ---
// WH requires software NOP insertion after 2-cycle instructions (E-004).
// The errata pass handles this, but the model reflects true latencies.

def TensixWHModel : SchedMachineModel {
  let IssueWidth = 1;
  let MicroOpBufferSize = 0;
  let LoadLatency = 2;
  let MispredictPenalty = 5;
  let CompleteModel = 0;
  let PostRAScheduler = 1;
}

let SchedModel = TensixWHModel in {

  def : WriteRes<WriteSFPUSimple, [SFPUSimpleUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPULoad, [SFPULoadUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPUStore, [SFPUStoreUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPURound, [SFPURoundUnit]> {
    let Latency = 1;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPUNop, []> {
    let Latency = 1;
  }

  // 2-cycle operations on WH — errata pass inserts SFPNOP after these
  def : WriteRes<WriteSFPUMAD, [SFPUMADUnit]> {
    let Latency = 2;
    let ReleaseAtCycles = [1];
  }

  def : WriteRes<WriteSFPUSwap, [SFPUSimpleUnit]> {
    let Latency = 2;
    let ReleaseAtCycles = [2];   // SFPSWAP requires SFPNOP on next cycle
  }

  def : WriteRes<WriteSFPULUTFP32, [SFPUMADUnit]> {
    let Latency = 2;
    let ReleaseAtCycles = [2];
  }

  // SFPSHFT2 on WH: 2 cycles for SHFLSHR1 mode (E-002 workaround adds dead
  // rotate), 1 cycle for other modes. Model conservatively as 2.
  def : WriteRes<WriteSFPUShft2, [SFPUSimpleUnit]> {
    let Latency = 2;
    let ReleaseAtCycles = [2];
  }

  def : ReadAdvance<ReadSFPUSrc, 0>;

} // SchedModel = TensixWHModel
