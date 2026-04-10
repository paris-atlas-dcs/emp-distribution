#!/bin/bash
# validate-systemd.sh — Validate systemd unit files and boot chain
#
# Usage: ./tests/validate-systemd.sh [systemd-dir]
#   Default: ./systemd/
#
# Runs on the host. No Docker needed. Checks syntax, dependencies, ordering.

set -euo pipefail

UNIT_DIR="${1:-$(dirname "$0")/../systemd}"
UNIT_DIR="$(cd "$UNIT_DIR" && pwd)"

echo "=== Systemd Boot Chain Validation ==="
echo "Unit dir: $UNIT_DIR"
echo ""

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

get_field() { grep -E "^${2}\s*=" "$1" 2>/dev/null | head -1 | sed "s/^${2}\s*=\s*//" ; }

has_dep() {
    local file="$1" key="$2" dep="$3"
    local val; val=$(get_field "$file" "$key")
    echo "$val" | grep -q "$dep"
}

# --- All units present ---
echo "--- Presence ---"
for u in emp-firmware.service emp-clock.service emp-reset.service \
         opcua-lpgbt.service opcua-psmon.service opcua-empmon.service \
         tempMonitor.service tempMonitor.timer emp-firstboot.service; do
    [ -f "$UNIT_DIR/$u" ] && pass "$u" || fail "missing $u"
done

# --- Dependency chain ---
echo "--- Boot chain ordering ---"
# emp-clock After emp-firmware
has_dep "$UNIT_DIR/emp-clock.service" "After" "emp-firmware" \
    && pass "emp-clock After emp-firmware" || fail "emp-clock missing After=emp-firmware"
has_dep "$UNIT_DIR/emp-clock.service" "Requires" "emp-firmware" \
    && pass "emp-clock Requires emp-firmware" || fail "emp-clock missing Requires=emp-firmware"

# emp-reset After emp-clock
has_dep "$UNIT_DIR/emp-reset.service" "After" "emp-clock" \
    && pass "emp-reset After emp-clock" || fail "emp-reset missing After=emp-clock"
has_dep "$UNIT_DIR/emp-reset.service" "Requires" "emp-clock" \
    && pass "emp-reset Requires emp-clock" || fail "emp-reset missing Requires=emp-clock"

# opcua-lpgbt After emp-reset
has_dep "$UNIT_DIR/opcua-lpgbt.service" "After" "emp-reset" \
    && pass "opcua-lpgbt After emp-reset" || fail "opcua-lpgbt missing After=emp-reset"
has_dep "$UNIT_DIR/opcua-lpgbt.service" "Requires" "emp-reset" \
    && pass "opcua-lpgbt Requires emp-reset" || fail "opcua-lpgbt missing Requires=emp-reset"

# opcua-empmon After emp-clock
has_dep "$UNIT_DIR/opcua-empmon.service" "After" "emp-clock" \
    && pass "opcua-empmon After emp-clock" || fail "opcua-empmon missing After=emp-clock"
has_dep "$UNIT_DIR/opcua-empmon.service" "Requires" "emp-clock" \
    && pass "opcua-empmon Requires emp-clock" || fail "opcua-empmon missing Requires=emp-clock"

# opcua-psmon is independent
echo "--- psmon independence ---"
for dep in emp-firmware emp-clock emp-reset; do
    if has_dep "$UNIT_DIR/opcua-psmon.service" "Requires" "$dep" 2>/dev/null; then
        fail "opcua-psmon should NOT require $dep"
    else
        pass "opcua-psmon independent of $dep"
    fi
done

# --- Oneshot services have RemainAfterExit ---
echo "--- Oneshot + RemainAfterExit ---"
for u in emp-firmware.service emp-clock.service emp-reset.service; do
    type=$(get_field "$UNIT_DIR/$u" "Type")
    rae=$(get_field "$UNIT_DIR/$u" "RemainAfterExit")
    [ "$type" = "oneshot" ] && pass "$u Type=oneshot" || fail "$u Type=$type (expected oneshot)"
    [ "$rae" = "yes" ] && pass "$u RemainAfterExit=yes" || fail "$u RemainAfterExit=$rae (expected yes)"
done

# --- Timer fields ---
echo "--- Timer ---"
t="$UNIT_DIR/tempMonitor.timer"
if [ -f "$t" ]; then
    obs=$(get_field "$t" "OnBootSec")
    uas=$(get_field "$t" "OnUnitActiveSec")
    unit=$(get_field "$t" "Unit")
    [ -n "$obs" ] && pass "OnBootSec=$obs" || fail "missing OnBootSec"
    [ -n "$uas" ] && pass "OnUnitActiveSec=$uas" || fail "missing OnUnitActiveSec"
    [ "$unit" = "tempMonitor.service" ] && pass "Unit=tempMonitor.service" || fail "Unit=$unit"
fi

# --- Summary ---
echo ""
echo "======================================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "======================================="
[ "$FAIL" -eq 0 ]
