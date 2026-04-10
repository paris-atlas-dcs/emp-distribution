#!/bin/bash
# run-all.sh — Run all test suites against an EMP distribution bundle
#
# Usage: ./tests/run-all.sh emp-2026.04.5.tar.gz
#
# Runs in order:
#   1. validate-bundle.sh  — structure, types, permissions (host, instant)
#   2. validate-systemd.sh — boot chain ordering (host, instant)
#   3. smoke-test.sh       — servers + tools in Docker QEMU (~60s)

set -euo pipefail

TARBALL="${1:?Usage: $0 <emp-VERSION.tar.gz>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
RESULTS=""

run_test() {
    local name="$1" script="$2"
    shift 2
    echo ""
    echo "################################################################"
    echo "  $name"
    echo "################################################################"
    echo ""
    if bash "$script" "$@" 2>&1; then
        RESULTS="$RESULTS\n  PASS  $name"
        TOTAL_PASS=$((TOTAL_PASS+1))
    else
        RESULTS="$RESULTS\n  FAIL  $name"
        TOTAL_FAIL=$((TOTAL_FAIL+1))
    fi
}

echo "=== EMP Distribution Test Suite ==="
echo "Tarball: $TARBALL"
echo "Date:    $(date)"

run_test "Bundle Validation" "$SCRIPT_DIR/validate-bundle.sh" "$TARBALL"
run_test "Systemd Boot Chain" "$SCRIPT_DIR/validate-systemd.sh"
run_test "Smoke Test (Docker QEMU)" "$SCRIPT_DIR/smoke-test.sh" "$TARBALL"

echo ""
echo "################################################################"
echo "  OVERALL RESULTS"
echo "################################################################"
echo -e "$RESULTS"
echo ""
echo "  Suites passed: $TOTAL_PASS"
echo "  Suites failed: $TOTAL_FAIL"
echo "################################################################"

[ "$TOTAL_FAIL" -eq 0 ]
