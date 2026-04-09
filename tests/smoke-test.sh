#!/bin/bash
# smoke-test.sh — Start OPC UA servers with simulators in Docker QEMU
#
# Usage: ./tests/smoke-test.sh emp-2026.04.4.tar.gz
#
# Requires: Docker with aarch64 QEMU support
#   docker run --rm --platform linux/arm64 almalinux:9 uname -m  # should print aarch64
#
# What it does:
#   1. Extracts the bundle
#   2. Starts OpcUaLpGbtServer with lpgbt-simulator:// config
#   3. Starts psMonServer with psu-simulator:// config
#   4. Verifies both open OPC UA endpoints
#   5. Runs lpGbtIdentify --help to verify CLI tools work

set -euo pipefail

TARBALL="${1:?Usage: $0 <emp-VERSION.tar.gz>}"
TARBALL_ABS="$(cd "$(dirname "$TARBALL")" && pwd)/$(basename "$TARBALL")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

cat > "$TMPDIR/run-tests.sh" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

cd /bundle

echo "--- Binary existence ---"
[ -x OpcUaLpGbtServer/bin/OpcUaLpGbtServer ] && pass "OpcUaLpGbtServer" || fail "OpcUaLpGbtServer missing"
[ -x psMonServer/bin/psMonServer ] && pass "psMonServer" || fail "psMonServer missing"

echo "--- CLI tools ---"
for tool in OpcUaLpGbtServer/tools/bin/lpGbtIdentify OpcUaLpGbtServer/tools/bin/lpgbt; do
    [ -x "$tool" ] || { fail "missing $tool"; continue; }
    LD_LIBRARY_PATH="OpcUaLpGbtServer/tools/lib" timeout 5 "$tool" --help >/dev/null 2>&1; rc=$?
    [ $rc -ne 139 ] && pass "$(basename $tool) --help (exit $rc)" || fail "$(basename $tool) segfault"
done

echo "--- OpcUaLpGbtServer with simulator ---"
cp /configs/sim-lpgbt.xml OpcUaLpGbtServer/bin/
cd OpcUaLpGbtServer/bin
LD_LIBRARY_PATH=../lib timeout 15 ./OpcUaLpGbtServer --config_file sim-lpgbt.xml > /tmp/lpgbt.log 2>&1 &
LPID=$!
cd /bundle

echo "--- psMonServer with simulator ---"
cp /configs/sim-psmon.xml psMonServer/bin/
cd psMonServer/bin
LD_LIBRARY_PATH=../lib timeout 15 ./psMonServer --config_file sim-psmon.xml > /tmp/psmon.log 2>&1 &
PPID=$!
cd /bundle

# Wait for endpoints
echo "--- Waiting for endpoints (max 12s) ---"
for i in $(seq 1 12); do
    sleep 1
    lpgbt_ok=$(grep -c "Opened endpoint" /tmp/lpgbt.log 2>/dev/null || echo 0)
    psmon_ok=$(grep -c "Opened endpoint" /tmp/psmon.log 2>/dev/null || echo 0)
    [ "$lpgbt_ok" -gt 0 ] && [ "$psmon_ok" -gt 0 ] && break
done

[ "$lpgbt_ok" -gt 0 ] && pass "OpcUaLpGbtServer endpoint opened" || fail "OpcUaLpGbtServer no endpoint"
[ "$psmon_ok" -gt 0 ] && pass "psMonServer endpoint opened" || fail "psMonServer no endpoint"

# Show version from logs
grep -a "VERSION_STR\|version" /tmp/lpgbt.log 2>/dev/null | head -1 || true

# Cleanup
kill $LPID $PPID 2>/dev/null || true

echo ""
echo "======================================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "======================================="
[ "$FAIL" -eq 0 ]
SCRIPT
chmod +x "$TMPDIR/run-tests.sh"

# Run everything in aarch64 Docker
docker run --rm --platform linux/arm64 \
    -v "$TARBALL_ABS:/tarball.tar.gz:ro" \
    -v "$TMPDIR:/configs:ro" \
    -v "$TMPDIR/run-tests.sh:/run-tests.sh:ro" \
    almalinux:9 \
    bash -c "
        mkdir -p /bundle && tar xzf /tarball.tar.gz -C /bundle/ 2>/dev/null
        bash /run-tests.sh
    "
