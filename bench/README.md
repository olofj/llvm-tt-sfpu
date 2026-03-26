# SFPU Benchmark Suite

Comparative benchmark framework for GCC (sfpi-gcc) vs LLVM (XttSFPU) codegen.

## Quick Start

```bash
# Run all benchmarks, produce JUnit XML + JSON metrics
./bench/run_benchmarks.py

# Run with specific output format
./bench/run_benchmarks.py --format=junit --output=results/
./bench/run_benchmarks.py --format=json --output=results/

# Run specific benchmark category
./bench/run_benchmarks.py --category=ml_kernels
```

## Output Formats

- **JUnit XML** (`results/sfpu_bench.xml`) — CI integration, test dashboards
- **JSON metrics** (`results/metrics.json`) — time-series tracking, analysis
- **Console summary** — human-readable comparison table

## Benchmark Categories

| Category | Kernels | Description |
|----------|---------|-------------|
| `ml_kernels` | exp, gelu, sigmoid, tanh, softmax, recip, sqrt, rsqrt | Common ML activation/math |
| `scheduling` | independent_muls, interleaved_mads, load_store_chain | Pipeline utilization |
| `predication` | simple_vif, nested_vif, vif_velse, live_value | CC stack patterns |
| `comparison` | gt_lt, eq_ne, abs_cmp | Comparison instruction selection |
| `encoding` | all_opcodes, boundary_values, wh_bh_diff | Encoding correctness |

## Metrics Tracked

Per-kernel:
- `total_instructions` — count of emitted instructions
- `nop_count` — wasted NOP cycles
- `mad_count` — MAD vs separate MUL+ADD
- `estimated_cycles_bh` — cycle estimate for Blackhole
- `estimated_cycles_wh` — cycle estimate for Wormhole
- `register_pressure` — max simultaneous live LRegs
- `code_size_bytes` — total instruction bytes

Aggregate:
- `instruction_reduction_pct` — % fewer instructions vs GCC
- `nop_elimination_count` — NOPs removed
- `cycle_reduction_pct` — % fewer cycles on BH
