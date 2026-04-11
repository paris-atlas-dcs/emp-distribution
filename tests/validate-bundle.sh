#!/bin/bash
# validate-bundle.sh — Validate EMP software bundle structure and integrity
#
# Usage: ./tests/validate-bundle.sh emp-release-26.04.1.tar.gz
#
# Runs on the host (no Docker needed). Checks structure, file types,
# permissions, and consistency. Fast — no binary execution.

set -euo pipefail

TARBALL="${1:?Usage: $0 <emp-VERSION.tar.gz>}"
WORK=$(mktemp -d /tmp/emp-validate.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "=== EMP Bundle Validation ==="
echo "Tarball: $TARBALL"
tar xzf "$TARBALL" -C "$WORK" 2>/dev/null
echo ""

PASS=0; FAIL=0; WARN=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
warn() { WARN=$((WARN+1)); echo "  WARN  $1"; }

# --- 1. Required directories ---
echo "--- Structure ---"
for dir in \
    OpcUaLpGbtServer/bin OpcUaLpGbtServer/lib OpcUaLpGbtServer/Configuration \
    OpcUaLpGbtServer/tools/bin OpcUaLpGbtServer/tools/lib \
    psMonServer/bin psMonServer/lib psMonServer/Configuration \
    emp-tools/bin \
    systemd; do
    [ -d "$WORK/$dir" ] && pass "$dir/" || fail "missing $dir/"
done
for f in version manifest.yml; do
    [ -f "$WORK/$f" ] && pass "$f" || fail "missing $f"
done

# --- 2. Binaries are ELF aarch64 ---
echo "--- Binary architecture ---"
for bin in \
    OpcUaLpGbtServer/bin/OpcUaLpGbtServer \
    psMonServer/bin/psMonServer \
    OpcUaLpGbtServer/tools/bin/lpGbtIdentify \
    emp-tools/bin/clkProgrammer \
    emp-tools/bin/fwReset; do
    [ -f "$WORK/$bin" ] || { fail "missing $bin"; continue; }
    if file "$WORK/$bin" | grep -q "aarch64"; then
        pass "aarch64: $bin"
    else
        fail "not aarch64: $bin ($(file -b "$WORK/$bin" | head -c 40))"
    fi
done

# --- 3. Shared lib counts ---
echo "--- Shared libraries ---"
lpgbt_libs=$(ls "$WORK/OpcUaLpGbtServer/lib/"*.so* 2>/dev/null | wc -l | tr -d ' ')
psmon_libs=$(ls "$WORK/psMonServer/lib/"*.so* 2>/dev/null | wc -l | tr -d ' ')
tools_libs=$(ls "$WORK/OpcUaLpGbtServer/tools/lib/"*.so* 2>/dev/null | wc -l | tr -d ' ')
[ "$lpgbt_libs" -ge 20 ] && pass "OpcUaLpGbtServer/lib: $lpgbt_libs libs" || fail "OpcUaLpGbtServer/lib: only $lpgbt_libs libs (need >=20)"
[ "$psmon_libs" -ge 18 ] && pass "psMonServer/lib: $psmon_libs libs" || fail "psMonServer/lib: only $psmon_libs libs (need >=18)"
[ "$tools_libs" -ge 5 ] && pass "tools/lib: $tools_libs libs" || fail "tools/lib: only $tools_libs libs (need >=5)"

# --- 4. Systemd units ---
echo "--- Systemd units ---"
for svc in opcua-lpgbt.service opcua-psmon.service opcua-empmon.service \
           emp-firmware.service emp-clock.service emp-reset.service \
           tempMonitor.service tempMonitor.timer; do
    [ -f "$WORK/systemd/$svc" ] && pass "$svc" || fail "missing systemd/$svc"
done

# --- 5. No world-writable files ---
echo "--- Permissions ---"
ww=$(find "$WORK" -type f -perm -o+w 2>/dev/null | wc -l | tr -d ' ')
[ "$ww" -eq 0 ] && pass "no world-writable files" || fail "$ww world-writable file(s)"

# --- 6. No symlinks outside bundle ---
echo "--- Symlink safety ---"
bad_links=0
while IFS= read -r link; do
    target=$(readlink "$link")
    if [[ "$target" == /* ]] && [[ "$target" != "$WORK"* ]]; then
        fail "external symlink: $link -> $target"
        bad_links=$((bad_links+1))
    fi
done < <(find "$WORK" -type l 2>/dev/null)
[ "$bad_links" -eq 0 ] && pass "all symlinks are local"

# --- 7. Version consistency ---
echo "--- Version ---"
ver_file=$(cat "$WORK/version" 2>/dev/null | tr -d '[:space:]')
ver_manifest=$(python3 -c "import yaml; print(yaml.safe_load(open('$WORK/manifest.yml'))['distribution'])" 2>/dev/null | tr -d '[:space:]')
if [ -n "$ver_file" ]; then
    pass "version file: $ver_file"
else
    fail "version file empty or missing"
fi
if [ -n "$ver_manifest" ]; then
    pass "manifest.yml valid YAML, distribution=$ver_manifest"
else
    fail "manifest.yml invalid or missing distribution key"
fi

# --- 8. Duplicate libs ---
echo "--- Duplicate libraries (informational) ---"
dupes=$(comm -12 \
    <(ls "$WORK/OpcUaLpGbtServer/lib/" 2>/dev/null | sort) \
    <(ls "$WORK/psMonServer/lib/" 2>/dev/null | sort) | wc -l | tr -d ' ')
warn "$dupes shared libs duplicated between servers"

# --- Summary ---
echo ""
echo "======================================="
echo "  PASS: $PASS   FAIL: $FAIL   WARN: $WARN"
echo "======================================="
[ "$FAIL" -eq 0 ]
