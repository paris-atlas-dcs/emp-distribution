#!/bin/bash
# rollback.sh — Roll back to the previous software version
#
# Usage: ./rollback.sh <target-host>
#   e.g.: ./rollback.sh emp-test2

set -euo pipefail

TARGET="${1:?Usage: $0 <target-host>}"
REMOTE_BASE="/opt/emp"

echo "=== EMP Rollback ==="

# Find current and previous versions
CURRENT=$(ssh "$TARGET" "readlink $REMOTE_BASE/current | xargs basename")
PREVIOUS=$(ssh "$TARGET" "ls -1d $REMOTE_BASE/releases/*/ | sort -V | grep -v '$CURRENT' | tail -1 | xargs basename")

if [ -z "$PREVIOUS" ]; then
    echo "ERROR: No previous version found to roll back to"
    exit 1
fi

echo "Current:  $CURRENT"
echo "Rollback: $PREVIOUS"
read -p "Proceed? [y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 0

ssh "$TARGET" "ln -sfn $REMOTE_BASE/releases/$PREVIOUS $REMOTE_BASE/current.prev && \
    mv -T $REMOTE_BASE/current.prev $REMOTE_BASE/current && \
    echo $PREVIOUS > $REMOTE_BASE/version && \
    systemctl restart opcua-lpgbt opcua-psmon"

sleep 3
ssh "$TARGET" "systemctl is-active opcua-lpgbt opcua-psmon && \
    echo 'Rolled back to: $(cat $REMOTE_BASE/version)'"

echo "=== Rollback complete ==="
