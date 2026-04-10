#!/bin/bash
# emp-firstboot.sh — Expand root partition to fill the SD card
#
# Runs once on first boot, then disables itself by removing /opt/emp/.firstboot
# Called by emp-firstboot.service (ConditionPathExists guard)

set -euo pipefail

log() { echo "[emp-firstboot] $*" | tee -a /var/log/emp/firstboot.log; }

ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -z "$ROOT_DEV" ]; then
    log "ERROR: Cannot determine root device"
    exit 1
fi

# Extract disk and partition number (e.g., /dev/mmcblk0p2 → /dev/mmcblk0, 2)
DISK=$(echo "$ROOT_DEV" | sed 's/p[0-9]*$//')
PART_NUM=$(echo "$ROOT_DEV" | grep -o '[0-9]*$')

log "Root device: $ROOT_DEV (disk: $DISK, partition: $PART_NUM)"

# Check if growpart is available
if ! command -v growpart &>/dev/null; then
    # Try to install it
    dnf install -y cloud-utils-growpart 2>/dev/null || \
    yum install -y cloud-utils-growpart 2>/dev/null || {
        log "WARNING: growpart not available — skipping partition resize"
        log "Run manually: growpart $DISK $PART_NUM && resize2fs $ROOT_DEV"
        exit 0
    }
fi

# Grow the partition to fill available space
log "Growing partition $PART_NUM on $DISK..."
if growpart "$DISK" "$PART_NUM" 2>&1 | tee -a /var/log/emp/firstboot.log; then
    log "Partition grown successfully"
else
    rc=$?
    if [ $rc -eq 1 ]; then
        log "Partition already at maximum size (NOCHANGE)"
    else
        log "WARNING: growpart returned $rc"
    fi
fi

# Resize the filesystem
log "Resizing filesystem on $ROOT_DEV..."
resize2fs "$ROOT_DEV" 2>&1 | tee -a /var/log/emp/firstboot.log
log "Filesystem resized successfully"

# Log final size
df -h "$ROOT_DEV" | tee -a /var/log/emp/firstboot.log
log "First boot setup complete"
