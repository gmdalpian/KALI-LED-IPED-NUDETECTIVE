#!/bin/bash
# Sets disks to read-only using the blockdev command

source /usr/local/bin/forensic_utils.sh

root_system=$(get_boot_disk_name)

if [ -z "$root_system" ]
then
    root_system='null'
    boot_components=""
else
    # Gets a list of all devices derived from the boot disk
    # This includes physical partitions (e.g., sdb1) and dm mappings (e.g., Ventoy's dm-0)
    boot_components=$(lsblk -n -r -o KNAME "/dev/$root_system" 2>/dev/null)
fi

# Scans and creates all Windows Dynamic Disks (LDM) mappings
sudo ldmtool create all > /dev/null 2>&1

# Waits for the kernel and udev to finish creating the device nodes in /dev/
sudo udevadm settle

# Searches and sets recognized disks as read-only
# Using 'lsblk -l -n -o KNAME,TYPE' to ensure we get the correct kernel name (e.g., dm-0)
while read line ; do
    disk=`echo "$line" | awk '{print $1}'`
    
    # Checks if the exact KNAME is in the whitelist of boot disk components
    # The -w flag in grep ensures exact word matching (e.g., dm-0 won't match dm-01)
    if ! echo "$boot_components" | grep -w -q "$disk"
    then           
       sudo blockdev --setro /dev/$disk
    else
       sudo blockdev --setrw /dev/$disk
    fi
done <<< "$(lsblk -l -n -o KNAME,TYPE | grep -iE 'part|disk|rom|dm|ldm')"