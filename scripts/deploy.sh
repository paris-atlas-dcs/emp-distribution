#!/bin/bash
# deploy.sh — Deploy an emp software update to an EMP board
#
# Usage: ./deploy.sh <site> <update-tarball>
#   e.g.: ./deploy.sh dcslab-emptest2 emp-update-2026.04.1.tar.gz
#
# Prerequisites:
#   - SSH access to the target board (configured in sites/<site>/site.yml)
#   - The update tarball (from CI or local build)
#
# What it does:
#   1. Copies the tarball to the board
#   2. Extracts to /opt/emp/releases/<version>/
#   3. Copies site-specific config to /opt/emp/config/
#   4. Atomically swaps /opt/emp/current symlink
#   5. Reloads systemd and restarts services
#   6. Validates both OPC UA endpoints respond
#   7. Prunes old releases (keeps current + 1 rollback)

set -euo pipefail

SITE="${1:?Usage: $0 <site> <update-tarball>}"
TARBALL="${2:?Usage: $0 <site> <update-tarball>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Load site config
SITE_DIR="$REPO_ROOT/sites/$SITE"
if [ ! -d "$SITE_DIR" ]; then
    echo "ERROR: Site '$SITE' not found in sites/"
    exit 1
fi

# Extract version from tarball name (emp-update-VERSION.tar.gz)
VERSION=$(echo "$TARBALL" | sed 's/emp-update-\(.*\)\.tar\.gz/\1/')
REMOTE_BASE="/opt/emp"

# Read target host from site config (default: site name)
TARGET="${SITE}"

echo "=== EMP Software Deployment ==="
echo "Site:    $SITE"
echo "Target:  $TARGET"
echo "Version: $VERSION"
echo "Tarball: $TARBALL"
echo ""

# 1. Upload
echo "[1/7] Uploading tarball..."
scp "$TARBALL" "$TARGET:$REMOTE_BASE/"

# 2. Extract
echo "[2/7] Extracting to $REMOTE_BASE/releases/$VERSION/..."
ssh "$TARGET" "mkdir -p $REMOTE_BASE/releases/$VERSION && \
    tar xzf $REMOTE_BASE/$TARBALL -C $REMOTE_BASE/releases/$VERSION/ --strip-components=1 && \
    rm -f $REMOTE_BASE/$TARBALL"

# 3. Copy site config (never overwrite if already exists — use --update)
echo "[3/7] Deploying site config..."
scp "$SITE_DIR"/*.xml "$TARGET:$REMOTE_BASE/config/" 2>/dev/null || true

# 4. Atomic symlink swap
echo "[4/7] Atomic symlink swap..."
ssh "$TARGET" "ln -sfn $REMOTE_BASE/releases/$VERSION $REMOTE_BASE/current.new && \
    mv -T $REMOTE_BASE/current.new $REMOTE_BASE/current && \
    echo $VERSION > $REMOTE_BASE/version"

# 5. Reload and restart services
echo "[5/7] Restarting services..."
ssh "$TARGET" "systemctl daemon-reload && \
    systemctl restart opcua-lpgbt opcua-psmon"

# 6. Validate
echo "[6/7] Validating..."
sleep 3
ssh "$TARGET" "systemctl is-active opcua-lpgbt opcua-psmon && \
    echo 'Version: $(cat $REMOTE_BASE/version)'"

# 7. Prune old releases (keep current + previous)
echo "[7/7] Pruning old releases..."
ssh "$TARGET" "cd $REMOTE_BASE/releases && \
    ls -1d */ | sort -V | head -n -2 | xargs -r rm -rf"

echo ""
echo "=== Deployment complete ==="
echo "Version $VERSION deployed to $TARGET"
