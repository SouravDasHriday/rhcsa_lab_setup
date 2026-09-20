#!/bin/bash
# =============================================================================
# setup-disks.sh - Create virtual loop-backed block devices for RHCSA labs
# =============================================================================
# This script creates sparse disk image files and attaches them as loop devices,
# simulating /dev/vdb and /dev/vdc block devices for partitioning and LVM labs.
#
# Each server gets:
#   /dev/vdb - 5GB virtual disk (for partitioning, mkfs labs)
#   /dev/vdc - 5GB virtual disk (for LVM labs)
#   /dev/vdd - 2GB virtual disk (for swap/additional labs)
# =============================================================================

set -e

DISK_DIR="/var/disks"
LOG_FILE="/var/log/setup-disks.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [setup-disks] $*" | tee -a "$LOG_FILE"
}

# Create disk directory
mkdir -p "$DISK_DIR"

# Define disks: name, size_in_MB, loop_device, symlink
declare -A DISKS=(
    ["vdb"]="5120:/dev/loop10:/dev/vdb"
    ["vdc"]="5120:/dev/loop11:/dev/vdc"
    ["vdd"]="2048:/dev/loop12:/dev/vdd"
)

for disk_name in "${!DISKS[@]}"; do
    IFS=':' read -r size_mb loop_dev symlink <<< "${DISKS[$disk_name]}"
    img_file="${DISK_DIR}/${disk_name}.img"

    # Skip if already set up
    if [ -b "$symlink" ] && losetup "$loop_dev" &>/dev/null; then
        log "$disk_name already configured at $symlink -> $loop_dev"
        continue
    fi

    # Create sparse disk image if it doesn't exist
    if [ ! -f "$img_file" ]; then
        log "Creating sparse disk image: $img_file (${size_mb}MB)"
        dd if=/dev/zero of="$img_file" bs=1M count=0 seek="$size_mb" 2>/dev/null
    else
        log "Disk image already exists: $img_file"
    fi

    # Detach loop device if already attached to something else
    losetup -d "$loop_dev" 2>/dev/null || true

    # Attach loop device
    log "Attaching $img_file to $loop_dev"
    losetup "$loop_dev" "$img_file"

    # Create symlink
    rm -f "$symlink"
    ln -s "$loop_dev" "$symlink"
    log "Created symlink: $symlink -> $loop_dev"
done

# Verify setup
log "=== Disk Setup Summary ==="
for disk_name in vdb vdc vdd; do
    IFS=':' read -r size_mb loop_dev symlink <<< "${DISKS[$disk_name]}"
    if [ -b "$symlink" ]; then
        size=$(lsblk -bno SIZE "$loop_dev" 2>/dev/null || echo "unknown")
        log "  $symlink -> $loop_dev ($(( ${size:-0} / 1024 / 1024 ))MB) [OK]"
    else
        log "  $symlink [FAILED]"
    fi
done

log "Disk setup complete."
