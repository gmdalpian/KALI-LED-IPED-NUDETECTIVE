#!/bin/bash
# Wrapper script for udev to apply write protection
# It dynamically checks and ignores the boot device and its components

DEVICE="$1"
UTILS_SCRIPT="/usr/local/bin/forensic_utils.sh"

# Ensure basic PATH is available in the udev environment
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Advanced logging function for udev events
log() {
    local MSG="[Udev-Forensic-RO] $1"
    # Send to kernel ring buffer (dmesg)
    echo "$MSG" > /dev/kmsg 2>/dev/null
}

log "Event triggered for device: /dev/$DEVICE"

# Check if the initial boot service has finished its job
if [ ! -f "/run/forensic_boot_done" ]; then
    log "Boot initialization not finished yet. Ignoring coldplug event for /dev/$DEVICE."
    exit 0
fi

if [ -f "$UTILS_SCRIPT" ]; then
    # Source the centralized utility library
    source "$UTILS_SCRIPT"
    
    # Identify the parent boot disk
    root_system=$(get_boot_disk_name)
    
    if [ -n "$root_system" ]; then
        # Map all components derived from the boot disk
        boot_components=$(lsblk -n -r -o KNAME "/dev/$root_system" 2>/dev/null)
        
        # Check if the triggered device matches any boot component
        if echo "$boot_components" | grep -w -q "$DEVICE"; then
            # The device is part of the boot disk, exit cleanly without locking
            log "Device /dev/$DEVICE is part of the boot drive. Ignoring."
            exit 0
        fi
    fi
else
    log "WARNING: $UTILS_SCRIPT not found. Proceeding with default lock."
fi

# Apply read-only mode to non-boot devices
log "Applying read-only (RO) lock to /dev/$DEVICE"
if /sbin/blockdev --setro "/dev/$DEVICE"; then
    log "Success: /dev/$DEVICE is now read-only."
else
    log "Error: Failed to lock /dev/$DEVICE."
fi