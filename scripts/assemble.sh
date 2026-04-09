#!/bin/bash
# assemble.sh — Pull upstream release artifacts and assemble an update tarball
#
# Usage: ./assemble.sh [version]
#   Reads manifest.yml, downloads each component's release asset from GitHub,
#   and assembles a single emp-update-<version>.tar.gz
#
# Requires: gh (GitHub CLI), yq (YAML parser)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFEST="$REPO_ROOT/manifest.yml"

VERSION="${1:-$(yq '.distribution' "$MANIFEST")}"
STAGING="/tmp/emp-assemble-$$"
OUTPUT_DIR="$REPO_ROOT"
OUTPUT="emp-update-${VERSION}.tar.gz"

echo "=== EMP Distribution Assembly ==="
echo "Version: $VERSION"
echo "Manifest: $MANIFEST"
echo ""

rm -rf "$STAGING"
mkdir -p "$STAGING"

# Download each component (latest by default, pinned if tag is set)
for component in $(yq '.components | keys | .[]' "$MANIFEST"); do
    repo=$(yq ".components.$component.repo" "$MANIFEST")
    tag=$(yq ".components.$component.tag // \"\"" "$MANIFEST")
    asset=$(yq ".components.$component.asset" "$MANIFEST")

    if [ -n "$tag" ]; then
        echo "Downloading $component (pinned: $tag) from $repo..."
        gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$STAGING" --clobber
    else
        echo "Downloading $component (latest) from $repo..."
        gh release download --repo "$repo" --pattern "$asset" --dir "$STAGING" --clobber
    fi
done

# Extract server tarballs into structured layout
mkdir -p "$STAGING/bundle"

for tarball in "$STAGING"/*.tar.gz; do
    [ -f "$tarball" ] || continue
    echo "Extracting $(basename "$tarball")..."
    tar xzf "$tarball" -C "$STAGING/bundle/"
done

# Copy systemd units
mkdir -p "$STAGING/bundle/systemd"
cp "$REPO_ROOT/systemd"/*.service "$STAGING/bundle/systemd/"

# Write version manifest into the bundle
cp "$MANIFEST" "$STAGING/bundle/manifest.yml"
echo "$VERSION" > "$STAGING/bundle/version"

# Package
echo ""
echo "Packaging $OUTPUT..."
tar czf "$OUTPUT_DIR/$OUTPUT" -C "$STAGING/bundle" .

rm -rf "$STAGING"

SIZE=$(du -h "$OUTPUT_DIR/$OUTPUT" | cut -f1)
echo ""
echo "=== Assembly Complete ==="
echo "Output: $OUTPUT ($SIZE)"
echo ""
echo "Deploy with: ./scripts/deploy.sh <site> $OUTPUT"
