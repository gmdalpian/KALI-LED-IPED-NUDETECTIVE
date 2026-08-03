#!/bin/bash
# forensic_utils.sh - Central library for boot device detection and triage

# Returns the physical path of the boot partition (e.g., /dev/sdb1)
get_boot_phys_part() {
    # Added head -n 1 to avoid multiline output if mounted multiple times
    local boot_dev=$(findmnt -n -o SOURCE /run/live/medium | head -n 1)
    
    # Checks if boot is via Device Mapper (Ventoy)
    if [[ "$boot_dev" == *"/mapper/ventoy"* ]]; then
        # 'head -n 1' ensures we only get the first mapping,
        # bypassing multiline output in Ventoy's GRUB2 mode
        local map_id=$(sudo dmsetup table ventoy 2>/dev/null | head -n 1 | awk '{print $4}')
        
        if [[ -n "$map_id" ]]; then
            local dev_name=$(basename "$(readlink -f "/sys/dev/block/$map_id")")
            echo "/dev/$dev_name"
        else
            echo "$boot_dev"
        fi
    else
        echo "$boot_dev"
    fi
}

# Returns only the name of the boot parent disk (e.g., sdb)
get_boot_disk_name() {
    local phys_part=$(get_boot_phys_part)
    
    # ADDED -d (--nodeps) to lsblk to prevent it from listing nested 
    # devices (like loops or dm mappings) and returning multiple pknames
    local disk_name=$(lsblk -nd -o pkname "$phys_part" 2>/dev/null)
    
    if [[ -z "$disk_name" ]]; then
        basename "$phys_part"
    else
        echo "$disk_name"
    fi
}

# Returns the correct device for mounting IPED-TRIAGE (resolves dm-X)
get_triage_device() {
    local root_disk=$(get_boot_disk_name)
    local triage_dev=""
    local found=false

    while read -r part_name ; do
        local current_phys="/dev/$part_name"
        if sudo blkid "$current_phys" | grep -q 'IPED-TRIAGE'; then
            local holders_dir="/sys/class/block/$part_name/holders"
            if [ -d "$holders_dir" ] && [ "$(ls -A "$holders_dir")" ]; then
                for holder in $(ls "$holders_dir"); do
                    if sudo blkid "/dev/$holder" | grep -q 'IPED-TRIAGE'; then
                        triage_dev="/dev/$holder"
                        found=true; break
                    fi
                done
            fi
            if ! $found; then triage_dev="$current_phys"; found=true; fi
            [[ "$part_name" == *"$root_disk"* ]] && break
        fi
    done <<< "$(lsblk -lno NAME,TYPE | grep part | awk '{print $1}')"
    echo "$triage_dev"
}

# Command line interface for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        --boot-phys) get_boot_phys_part ;;
        --boot-disk) get_boot_disk_name ;;
        --triage-dev) get_triage_device ;;
        *) echo "Usage: $0 [--boot-phys | --boot-disk | --triage-dev]" ;;
    esac
fi