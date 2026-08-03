#!/bin/bash

# -----------------------------------------------------------------------------
# Forensic Automatic Mount Script (Read-Only)
#
# Purpose: Mount all detected block devices (except the
#          Live USB system) in read-only mode for forensic analysis.
#
# Features:
# - Mounts partitions, non-partitioned disks (superfloppy), LDM and BitLocker.
# - Ensures all mounts are READ-ONLY.
# - Prevents execution, device access and SUID (noexec, nodev, nosuid).
# - Prevents journal playback (noload for ext4, ro for ntfs).
# - Uses 'ntfs' driver for all NTFS partitions.
# - Checks if a device is already mounted.
# - Ignores the Live system disk (USB, CD/DVD, etc.).
# - Generates a final report with Zenity (can be disabled)
#   which includes SUCCESSES and ERRORS and disappears after 10s.
#
# Usage:
#   sudo ./mount_disks.sh
#   sudo ./mount_disks.sh --no-report (to disable Zenity report)
# -----------------------------------------------------------------------------

export TEXTDOMAIN="mount_disks"
export TEXTDOMAINDIR="/usr/share/locale" # Adjust to your local path if testing

source /usr/local/bin/forensic_utils.sh

MEDIA_DIR="/run/media"

# --- Initial Configuration ---

SHOW_REPORT=true
if [[ "$1" == "--no-report" ]]; then
  SHOW_REPORT=false
  echo "$(gettext "Zenity report at the end was disabled via parameter.")"
fi

# Temporary log file for final report
MOUNT_LOG=$(mktemp)
# Ensures the log is cleared on exit
trap 'rm -f "$MOUNT_LOG"' EXIT

# --- BitLocker Devices Pre-cache ---
echo "$(gettext "Checking BitLocker devices in advance...")"
# Stores the BDE devices list to avoid mounting in Section 1
BITLOCKER_DEVICES=$(sudo dislocker-find)

# Creates base directory for dislocker (only once)
sudo mkdir -p /dislocker

# --- Robust Live System Detection ---

echo "$(gettext "Identifying the Live system disk to exclude it...")"
ROOT_DISK_NAME=$(get_boot_disk_name)

if [[ -n "$ROOT_DISK_NAME" ]]; then
    printf "$(gettext "Live system disk identified: %s. This disk will be ignored.")\n" "$ROOT_DISK_NAME"
else
    echo "$(gettext "Warning: Failed to determine boot disk.")"
    ROOT_DISK_NAME="null_failsafe"
fi

# --- Forensic Mount Helper Function ---

mount_forensic() {
    local device_path="$1"
    local mount_point="$2"
    local device_name
    device_name=$(basename "$device_path")

    # 1. Ignore the Live system disk
    if [[ -n "$ROOT_DISK_NAME" && "$device_name" == *"$ROOT_DISK_NAME"* ]]; then
        return
    fi

    # 2. Check if already mounted
    if findmnt --mountpoint "$mount_point" &> /dev/null; then
        printf "$(gettext "%s is already mounted at %s. Ignoring.")\n" "$device_path" "$mount_point"
        return
    fi

    # 3. BITLOCKER CHECK (IMPROVEMENT)
    # Checks if device is in the BDE list. If so, skips,
    # because it will be handled by Section 3.
    if echo "$BITLOCKER_DEVICES" | grep -q "^$device_path$"; then
        printf "$(gettext "Ignoring %s (BitLocker detected, will be handled in Section 3).")\n" "$device_path"
        return
    fi

    # 4. Detect file system type
    local fs_type_output
    fs_type_output=$(lsblk -no FSTYPE "$device_path")
    
    local line_count
    line_count=$(echo "$fs_type_output" | wc -l)

    if [[ $line_count -gt 1 ]]; then
        printf "$(gettext "Ignoring %s (container device with partitions).")\n" "$device_path"
        return
    fi
    
    local fs_type="$fs_type_output"

    if [[ -z "$fs_type" ]]; then
        printf "$(gettext "Ignoring %s (no detectable file system).")\n" "$device_path"
        return
    fi
    
    # Base options, crucial for security and forensics
    local mount_options="ro,noexec,nodev,nosuid"
    local type_options="" # FS type options, e.g.: -t ntfs

    # 5. Add specific journal and type options
    if [[ "$fs_type" == "ntfs" ]]; then
        type_options="-t ntfs"
        
    elif [[ "$fs_type" == "ext3" || "$fs_type" == "ext4" ]]; then
        mount_options="$mount_options,noload"
        
    elif [[ "$fs_type" == "xfs" || "$fs_type" == "jfs" ]]; then
        mount_options="$mount_options,norecovery"
    fi

    # 6. Create mount point and mount
    printf "$(gettext "Trying to mount %s (Type: %s) at %s...")\n" "$device_path" "$fs_type" "$mount_point"
    sudo mkdir -p "$mount_point"
    
    if sudo mount -o "$mount_options" $type_options "$device_path" "$mount_point"; then
        printf "$(gettext "Success: %s mounted at %s")\n" "$device_path" "$mount_point"
        printf "$(gettext "SUCCESS: %s -> %s (Type: %s, Options: %s)")\n" "$device_path" "$mount_point" "${fs_type:-unknown}" "$mount_options" >> "$MOUNT_LOG"
    else
        printf "$(gettext "Error: Failed to mount %s at %s.")\n" "$device_path" "$mount_point"
        printf "$(gettext "ERROR: Failed to mount %s at %s.")\n" "$device_path" "$mount_point" >> "$MOUNT_LOG"
        sudo rmdir "$mount_point" &> /dev/null
    fi
}

# --- 1. Standard Partitions Mount ---

echo "$(gettext "Mounting standard partitions (read-only)...")"
while read -r line; do
    disk_name=$(echo "$line" | awk '{print $1}') # e.g., sda, sda1, sdb, sr0
    if [[ -n "$disk_name" ]]; then
        mount_forensic "/dev/$disk_name" "$MEDIA_DIR/$disk_name"
    fi
done <<< "$(lsblk -lno NAME,TYPE | grep -E 'part|disk|rom')"


# --- 2. LDM Mount (Windows RAID) ---
echo "$(gettext "Trying to mount LDM volumes (Windows RAID)...")"
sudo ldmtool create all > /dev/null 2>&1
sudo udevadm settle

while read -r ldm_name; do
    if [[ -n "$ldm_name" ]]; then
        mount_forensic "/dev/mapper/$ldm_name" "$MEDIA_DIR/$ldm_name"
    fi
done <<< "$(lsblk -lno NAME --filter "TYPE == 'ldm'")"


# --- 3. BitLocker Partitions Mount ---

echo "$(gettext "Checking BitLocker partitions (from pre-loaded list)...")"
# IMPROVEMENT: Iterates over $BITLOCKER_DEVICES instead of calling dislocker-find again
while read -r bde_device_path; do
    if [[ -n "$bde_device_path" ]]; then
        
        # FIX: Removed 'local' from variable declarations
        disk_name=$(basename "$bde_device_path") 
        decrypted_mount_point="$MEDIA_DIR/decrypted_$disk_name"
        dislocker_path="/dislocker/bitlocker_$disk_name"
        dislocker_file="$dislocker_path/dislocker-file"
        bde_mount_options="loop,ro,noexec,nodev,nosuid"

        if [[ -n "$ROOT_DISK_NAME" && "$disk_name" == *"$ROOT_DISK_NAME"* ]]; then
            printf "$(gettext "Ignoring BitLocker on %s (part of Live system).")\n" "$bde_device_path"
            continue
        fi

        if findmnt --mountpoint "$decrypted_mount_point" &> /dev/null; then
            printf "$(gettext "BitLocker of %s is already mounted at %s. Ignoring.")\n" "$bde_device_path" "$decrypted_mount_point"
            continue
        fi

        printf "$(gettext "BitLocker partition detected on %s")\n" "$bde_device_path"
        sudo mkdir -p "$dislocker_path"
        sudo mkdir -p "$decrypted_mount_point"
        
        sudo dislocker -V "$bde_device_path" -- "$dislocker_path" -r

        if sudo test -f "$dislocker_file"; then
            # Success (suspended)
            printf "$(gettext "BitLocker on %s is suspended. Mounting...")\n" "$bde_device_path"
            if sudo mount -o $bde_mount_options "$dislocker_file" "$decrypted_mount_point" -t ntfs; then
                printf "$(gettext "Success: BitLocker of %s mounted at %s")\n" "$bde_device_path" "$decrypted_mount_point"
                printf "$(gettext "SUCCESS: %s (BitLocker) -> %s (Type: ntfs, Options: %s)")\n" "$bde_device_path" "$decrypted_mount_point" "$bde_mount_options" >> "$MOUNT_LOG"
            else
                printf "$(gettext "Error: Failed to mount dislocker-file for %s.")\n" "$bde_device_path"
                printf "$(gettext "ERROR: Failed to mount dislocker-file for %s (suspended).")\n" "$bde_device_path" >> "$MOUNT_LOG"
                sudo rmdir "$decrypted_mount_point" "$dislocker_path" &> /dev/null
            fi
        else
            # 4. Needs key
            printf "$(gettext "BitLocker on %s requires a key.")\n" "$bde_device_path"
            
            while true; do
                BITLOCKER_INFO=('', '')
                previousline=""
                while read -r line ; do
                    if [[ ! -z $line ]]; then
                        if [[ $line =~ "Description:" ]]; then BITLOCKER_INFO[0]=$line; fi 
                        if [[ $line =~ "VMK protected with recovery passphrase" ]]; then BITLOCKER_INFO[1]=${previousline^^}; fi
                        previousline=$line;
                    fi
                done <<< "$(sudo cryptsetup bitlkDump "$bde_device_path")"

                # Pre-formatting for zenity texts to keep command clean
                zenity_title=$(gettext "BitLocker Detected!")
                zenity_text_format=$(gettext $'An encrypted bitlocker partition was detected on %s, but could not be decrypted automatically.\nThis script will try to mount the other partitions.\nIf you have the recovery key or password, enter it below:\n%s\n%s')
                zenity_text=$(printf "$zenity_text_format" "$bde_device_path" "${BITLOCKER_INFO[0]}" "${BITLOCKER_INFO[1]}")
                zenity_entry=$(gettext "RecoveryKey")

                bitlocker_pass=$(zenity --entry --title="$zenity_title" --text="$zenity_text" --entry-text "$zenity_entry" --width=500 2>/dev/null)
                
                if [ $? = 0 ]; then
                    # Tries with Recovery Key
                    sudo dislocker -V "$bde_device_path" -p"$bitlocker_pass" -- "$dislocker_path" -r
                    if sudo test -f "$dislocker_file"; then
                        echo "$(gettext "Recovery key accepted. Mounting...")"
                        if sudo mount -o $bde_mount_options "$dislocker_file" "$decrypted_mount_point" -t ntfs; then
                            printf "$(gettext "Success: BitLocker of %s mounted at %s")\n" "$bde_device_path" "$decrypted_mount_point"
                            printf "$(gettext "SUCCESS: %s (BitLocker) -> %s (Type: ntfs, Options: %s)")\n" "$bde_device_path" "$decrypted_mount_point" "$bde_mount_options" >> "$MOUNT_LOG"
                        else
                            printf "$(gettext "Error: Failed to mount dislocker-file for %s.")\n" "$bde_device_path"
                            printf "$(gettext "ERROR: Failed to mount dislocker-file for %s (with Key).")\n" "$bde_device_path" >> "$MOUNT_LOG"
                        fi
                        break
                    else
                        # Tries with User Password
                        sudo dislocker -V "$bde_device_path" --user-password="$bitlocker_pass" -- "$dislocker_path" -r
                        if sudo test -f "$dislocker_file"; then
                            echo "$(gettext "User password accepted. Mounting...")"
                            if sudo mount -o $bde_mount_options "$dislocker_file" "$decrypted_mount_point" -t ntfs; then
                                printf "$(gettext "Success: BitLocker of %s mounted at %s")\n" "$bde_device_path" "$decrypted_mount_point"
                                printf "$(gettext "SUCCESS: %s (BitLocker) -> %s (Type: ntfs, Options: %s)")\n" "$bde_device_path" "$decrypted_mount_point" "$bde_mount_options" >> "$MOUNT_LOG"
                            else
                                printf "$(gettext "Error: Failed to mount dislocker-file for %s.")\n" "$bde_device_path"
                                printf "$(gettext "ERROR: Failed to mount dislocker-file for %s (with Password).")\n" "$bde_device_path" >> "$MOUNT_LOG"
                            fi
                            break
                        else
                            zenity_err_title=$(gettext "BitLocker Key Error!")
                            zenity_err_text=$(gettext "The provided key or password did not decrypt the drive.")
                            zenity --error --title="$zenity_err_title" --text="$zenity_err_text" --width=300 --timeout=20 2>/dev/null
                            printf "$(gettext "ERROR: Invalid Key/Password provided for %s.")\n" "$bde_device_path" >> "$MOUNT_LOG"
                        fi
                    fi
                else
                    printf "$(gettext "BitLocker mount on %s canceled by user.")\n" "$bde_device_path"
                    printf "$(gettext "WARNING: BitLocker mount on %s canceled by user.")\n" "$bde_device_path" >> "$MOUNT_LOG"
                    sudo rmdir "$decrypted_mount_point" "$dislocker_path" &> /dev/null
                    break
                fi
            done
        fi
    fi
done <<< "$BITLOCKER_DEVICES" # IMPROVEMENT: Uses pre-loaded variable


# --- 4. Final Report ---

echo "$(gettext "Mounting process completed.")"

if [ "$SHOW_REPORT" = true ]; then
    REPORT_CONTENT=$(cat "$MOUNT_LOG")
    if [ -z "$REPORT_CONTENT" ]; then
        zenity_info_title=$(gettext "Mount Report")
        zenity_info_text=$(gettext "No mount activity (success or error) was recorded.")
        zenity --info --title="$zenity_info_title" --text="$zenity_info_text" --width=400 --timeout=10 2>/dev/null
    else
        zenity_report_title=$(gettext "Forensic Mount Report")
        zenity_report_header=$(gettext "Mount Report (Secure Forensic Mode):")
        echo -e "${zenity_report_header}\n\n$REPORT_CONTENT" | zenity --text-info --title="$zenity_report_title" --width=700 --height=400 --font="Monospace" --timeout=10 2>/dev/null
    fi
else
    echo "$(gettext "Zenity report disabled. Console output:")"
    if [ -s "$MOUNT_LOG" ]; then
        cat "$MOUNT_LOG"
    else
        echo "$(gettext "No mount activity (success or error) was recorded.")"
    fi
fi

# The $MOUNT_LOG cleanup is handled by the 'trap' at the beginning.