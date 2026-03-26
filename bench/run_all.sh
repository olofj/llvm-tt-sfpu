#!/bin/bash
# run_all.sh — Run complete SFPU test + benchmark suite
#
# Produces:
#   bench/results/sfpu_bench.xml     — JUnit XML (codegen benchmarks)
#   bench/results/metrics.json       — JSON metrics (codegen benchmarks)
#   bench/results/encoding.xml       — JUnit XML (encoding validation)
#   bench/results/encoding.json      — JSON (encoding details)
#
# Exit code: 0 if all pass, 1 if any failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/bench/results"

mkdir -p "$RESULTS_DIR"

echo "=========================================="
echo "SFPU Test + Benchmark Suite"
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

FAILURES=0

# ---- Phase 1: Encoding Validation ----
echo ""
echo "=== Phase 1: Encoding Validation ==="

# BH/WH cross-validation
echo "  Running BH/WH encoding validation..."
if python3 "$PROJECT_DIR/scripts/validate_encoding.py" > /dev/null 2>&1; then
    BH_WH_RESULT="PASS"
    BH_WH_COUNT=46
else
    BH_WH_RESULT="FAIL"
    FAILURES=$((FAILURES + 1))
    BH_WH_COUNT=0
fi
echo "  BH/WH cross-validation: $BH_WH_RESULT ($BH_WH_COUNT tests)"

# Exhaustive opcode validation
echo "  Running exhaustive opcode validation..."
EXHAUSTIVE_OUTPUT=$(python3 "$PROJECT_DIR/scripts/validate_all_opcodes.py" 2>&1)
EXHAUSTIVE_EXIT=$?
EXHAUSTIVE_TOTAL=$(echo "$EXHAUSTIVE_OUTPUT" | grep "^Total:" | grep -oP '\d+(?= encoding)')
EXHAUSTIVE_FAIL=$(echo "$EXHAUSTIVE_OUTPUT" | grep "^Total:" | grep -oP '\d+(?= failure)')

if [ "$EXHAUSTIVE_EXIT" -eq 0 ]; then
    echo "  Exhaustive opcodes: PASS ($EXHAUSTIVE_TOTAL tests)"
else
    echo "  Exhaustive opcodes: FAIL ($EXHAUSTIVE_FAIL failures out of $EXHAUSTIVE_TOTAL tests)"
    FAILURES=$((FAILURES + 1))
fi

# Generate encoding JUnit XML
python3 -c "
from xml.etree.ElementTree import Element, SubElement, tostring, indent
from datetime import datetime, timezone

root = Element('testsuites')
root.set('name', 'SFPU Encoding Validation')
root.set('timestamp', datetime.now(timezone.utc).isoformat())
root.set('tests', '2')
root.set('failures', '$FAILURES')

suite = SubElement(root, 'testsuite')
suite.set('name', 'sfpu.encoding')
suite.set('tests', '2')

tc1 = SubElement(suite, 'testcase')
tc1.set('name', 'bh_wh_cross_validation')
tc1.set('classname', 'sfpu.encoding')
props1 = SubElement(tc1, 'properties')
p = SubElement(props1, 'property'); p.set('name', 'test_count'); p.set('value', '46')

tc2 = SubElement(suite, 'testcase')
tc2.set('name', 'exhaustive_opcodes')
tc2.set('classname', 'sfpu.encoding')
props2 = SubElement(tc2, 'properties')
p = SubElement(props2, 'property'); p.set('name', 'test_count'); p.set('value', '$EXHAUSTIVE_TOTAL')

indent(root, space='  ')
print('<?xml version=\"1.0\" encoding=\"UTF-8\"?>')
print(tostring(root, encoding='unicode'))
" > "$RESULTS_DIR/encoding.xml"

echo "  Output: $RESULTS_DIR/encoding.xml"

# ---- Phase 2: Codegen Benchmarks ----
echo ""
echo "=== Phase 2: Codegen Benchmarks ==="

python3 "$PROJECT_DIR/bench/run_benchmarks.py" --output="$RESULTS_DIR" 2>&1
BENCH_EXIT=$?

if [ "$BENCH_EXIT" -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
fi

# ---- Phase 3: Summary ----
echo ""
echo "=========================================="
echo "SUITE SUMMARY"
echo "=========================================="

TOTAL_ENCODING=$((46 + EXHAUSTIVE_TOTAL))
echo "  Encoding tests: $TOTAL_ENCODING (BH/WH: 46, Exhaustive: $EXHAUSTIVE_TOTAL)"
echo "  Codegen benchmarks: 13 kernels"

BENCH_SUMMARY=$(python3 -c "import json; d=json.load(open('$RESULTS_DIR/metrics.json')); s=d['summary']; print(f\"  Instruction reduction: {s['instruction_reduction_pct']}%\"); print(f\"  NOPs eliminated: {s['nops_eliminated']}\")")
echo "$BENCH_SUMMARY"

echo ""
echo "  Results directory: $RESULTS_DIR/"
ls -la "$RESULTS_DIR/"

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "ALL TESTS PASSED"
    exit 0
else
    echo "FAILURES: $FAILURES"
    exit 1
fi
