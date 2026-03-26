//===-- RISCVFeaturesXttSFPU.td - XttSFPU Feature Defs -----*- tablegen -*-===//
//
// Feature flag definitions for the Tenstorrent SFPU vendor extension.
// These are added to RISCVFeatures.td via include.
//
// Three features:
//   XttSFPU    — Base SFPU ISA (38 opcodes, 0x70-0x95)
//   XttSFPUBH  — Blackhole extensions (SFPMUL24, SFPARECIP, SFPGT, SFPLE,
//                SFPMOV_CONFIG, 3-bit addr_mode, hardware scoreboarding)
//   XttSFPUWH  — Wormhole extensions (2-bit addr_mode, dst=src_a constraint,
//                software NOP insertion required)
//
// Usage: -mattr=+xttsfpu,+xttsfpu-bh for Blackhole targets
//        -mattr=+xttsfpu,+xttsfpu-wh for Wormhole targets
//
// Reference: ttsim-analysis/ERRATA.md C-009, C-010, C-011
//
//===----------------------------------------------------------------------===//

def FeatureVendorXttSFPU
    : SubtargetFeature<"xttsfpu", "HasXttSFPU", "true",
                       "'XttSFPU' (Tenstorrent SFPU Vector Unit base ISA)">;

def FeatureVendorXttSFPUBH
    : SubtargetFeature<"xttsfpu-bh", "HasXttSFPUBH", "true",
                       "'XttSFPU-BH' (Tenstorrent SFPU Blackhole extensions)",
                       [FeatureVendorXttSFPU]>;

def FeatureVendorXttSFPUWH
    : SubtargetFeature<"xttsfpu-wh", "HasXttSFPUWH", "true",
                       "'XttSFPU-WH' (Tenstorrent SFPU Wormhole extensions)",
                       [FeatureVendorXttSFPU]>;

// Processor definitions are in RISCVSchedXttSFPU.td (needs scheduling model first).
