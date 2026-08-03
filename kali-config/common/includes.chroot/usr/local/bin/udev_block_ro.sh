#!/bin/bash
# Wrapper script for udev to apply write protection
# It dynamically checks and ignores the boot device and its components

DEVICE="$1"
UTILS_SCRIPT="/usr/local/bin/forensic_utils.sh"

# Ensure basic PATH is available in the udev environment
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

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
            exit 0
        fi
    fi
fi

# Apply read-only mode to non-boot devices
/sbin/blockdev --setro "/dev/$DEVICE"