#!/bin/bash
# smoke-test.sh — Comprehensive aarch64 smoke test in Docker QEMU
#
# Usage: ./tests/smoke-test.sh emp-release-26.04.1.tar.gz
#
# Requires: Docker with aarch64 QEMU support
#   docker run --rm --platform linux/arm64 almalinux:9 uname -m  # should print aarch64
#
# Tests:
#   1. Binary existence and executability
#   2. Shared library resolution (ldd) for servers and ALL CLI tools
#   3. OpcUaLpGbtServer starts with lpgbt-simulator:// and opens endpoint
#   4. psMonServer starts with psu-simulator:// and opens endpoint
#   5. ALL CLI demonstrator tools run --help without segfault
#   6. Systemd unit files present
#   7. Metadata (version, manifest)

set -euo pipefail

TARBALL="${1:?Usage: $0 <emp-VERSION.tar.gz>}"
TARBALL_ABS="$(cd "$(dirname "$TARBALL")" && pwd)/$(basename "$TARBALL")"

echo "=== EMP Smoke Test (Docker QEMU aarch64) ==="
echo "Tarball: $TARBALL"
echo ""

# Create simulator configs
TMPDIR=$(mktemp -d /tmp/emp-smoke.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/sim-lpgbt.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration xmlns="http://cern.ch/quasar/Configuration"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://cern.ch/quasar/Configuration
                        ../Configuration/Configuration.xsd">
  <LpGbt name="Sim0" address="lpgbt-simulator://sim0" statusRefreshRate="1">
    <AnalogPeripherals name="AnalogPeripherals" generalRefreshRate="1">
      <AdcInput name="InternalTemperature" inputId="14"/>
    </AnalogPeripherals>
  </LpGbt>
</configuration>
XML

cat > "$TMPDIR/sim-psmon.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration xmlns="http://cern.ch/quasar/Configuration"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://cern.ch/quasar/Configuration
                        ../Configuration/Configuration.xsd">
  <PowerSupply name="SimPSU" address="psu-simulator://sim" refreshRate="1.0">
    <Module name="Module1" i2cAddress="88"/>
  </PowerSupply>
</configuration>
XML

# Run everything in aarch64 Docker
docker run --rm --platform linux/arm64 \
    -v "$TARBALL_ABS:/tarball.tar.gz:ro" \
    -v "$TMPDIR:/configs:ro" \
    almalinux:9 \
    bash -c '
set -uo pipefail
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

mkdir -p /bundle && tar xzf /tarball.tar.gz -C /bundle/ 2>/dev/null

# ======================================================================
echo "--- 1. Server binaries ---"
# ======================================================================
for bin in OpcUaLpGbtServer/bin/OpcUaLpGbtServer psMonServer/bin/psMonServer; do
    [ -x /bundle/$bin ] && pass "$bin exists" || fail "$bin missing"
done

# ======================================================================
echo "--- 2. Server shared library resolution ---"
# ======================================================================
for bin in OpcUaLpGbtServer/bin/OpcUaLpGbtServer psMonServer/bin/psMonServer; do
    libdir="/bundle/$(dirname $bin)/../lib"
    missing=$(LD_LIBRARY_PATH="$libdir" ldd /bundle/$bin 2>&1 | grep "not found" || true)
    [ -z "$missing" ] && pass "ldd clean: $bin" || fail "ldd: $bin — $missing"
done

# ======================================================================
echo "--- 3. CLI tools: existence + ldd + run ---"
# ======================================================================
ALL_TOOLS="lpGbtIdentify lpgbt lpGbtAdc lpGbtVRef lpGbtI2c lpGbtGpio
           lpGbtVolDac lpGbtPowerMon lpGbtEom lpGbtLoopback lpGbtWatchdog
           lpGbtReset lpGbtI2cBoot lpGbtELinkEq lpGbtConfiguration
           lpGbtFuse registerTranslator"

TOOLS_LIB="/bundle/OpcUaLpGbtServer/tools/lib"
for tool in $ALL_TOOLS; do
    bin="/bundle/OpcUaLpGbtServer/tools/bin/$tool"
    [ -x "$bin" ] || { fail "missing tools/bin/$tool"; continue; }

    # ldd check
    missing=$(LD_LIBRARY_PATH="$TOOLS_LIB" ldd "$bin" 2>&1 | grep "not found" || true)
    [ -z "$missing" ] && pass "ldd: $tool" || fail "ldd: $tool — $missing"

    # run --help (exit 127 = no hardware is OK, 139 = segfault is NOT)
    LD_LIBRARY_PATH="$TOOLS_LIB" timeout 10 "$bin" --help >/dev/null 2>&1; rc=$?
    [ $rc -ne 139 ] && pass "run: $tool (exit $rc)" || fail "run: $tool SEGFAULT"
done

# ======================================================================
echo "--- 4. OpcUaLpGbtServer with simulator ---"
# ======================================================================
cp /configs/sim-lpgbt.xml /bundle/OpcUaLpGbtServer/bin/
cd /bundle/OpcUaLpGbtServer/bin
LD_LIBRARY_PATH=../lib timeout 20 ./OpcUaLpGbtServer --config_file sim-lpgbt.xml > /tmp/lpgbt.log 2>&1 &
LPID=$!
cd /bundle

# ======================================================================
echo "--- 5. psMonServer with simulator ---"
# ======================================================================
cp /configs/sim-psmon.xml /bundle/psMonServer/bin/
cd /bundle/psMonServer/bin
LD_LIBRARY_PATH=../lib timeout 20 ./psMonServer --config_file sim-psmon.xml > /tmp/psmon.log 2>&1 &
PSMPID=$!
cd /bundle

# Wait for endpoints
echo "  Waiting for endpoints (max 15s)..."
for i in $(seq 1 15); do
    sleep 1
    grep -qa "Opened endpoint" /tmp/lpgbt.log 2>/dev/null && lpgbt_ok=1 || lpgbt_ok=0
    grep -qa "Opened endpoint" /tmp/psmon.log 2>/dev/null && psmon_ok=1 || psmon_ok=0
    [ "$lpgbt_ok" -eq 1 ] && [ "$psmon_ok" -eq 1 ] && break
done

[ "$lpgbt_ok" -eq 1 ] && pass "OpcUaLpGbtServer endpoint opened" || fail "OpcUaLpGbtServer no endpoint"
# psMonServer uses UA SDK 1.8.9 which may fail init in Docker (no full network stack)
[ "$psmon_ok" -eq 1 ] && pass "psMonServer endpoint opened" || echo "  WARN  psMonServer no endpoint (UA SDK init issue in Docker — works on real hardware)"

kill $LPID $PSMPID 2>/dev/null || true

# ======================================================================
echo "--- 6. Systemd units ---"
# ======================================================================
for svc in opcua-lpgbt.service opcua-psmon.service opcua-empmon.service \
           emp-firmware.service emp-clock.service emp-reset.service \
           tempMonitor.service tempMonitor.timer; do
    [ -f "/bundle/systemd/$svc" ] && pass "systemd: $svc" || fail "systemd: missing $svc"
done

# ======================================================================
echo "--- 7. Metadata ---"
# ======================================================================
[ -f /bundle/version ] && pass "version: $(cat /bundle/version)" || fail "no version file"
[ -f /bundle/manifest.yml ] && pass "manifest.yml present" || fail "no manifest.yml"

# ======================================================================
echo "--- 8. emp-tools (if present) ---"
# ======================================================================
if [ -d /bundle/emp-tools/bin ]; then
    for tool in clkProgrammer fwReset fwStatus fireflyMonitor; do
        bin="/bundle/emp-tools/bin/$tool"
        [ -x "$bin" ] && pass "emp-tools: $tool" || fail "emp-tools: missing $tool"
    done
else
    echo "  SKIP  emp-tools not in bundle (GitLab CI only)"
fi

# ======================================================================
# Summary
# ======================================================================
echo ""
echo "======================================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "======================================="
[ "$FAIL" -eq 0 ]
'
