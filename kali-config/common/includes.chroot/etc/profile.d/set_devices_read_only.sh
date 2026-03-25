#!/bin/bash
# seta os discos como somente leitura pelo comando blockdev

source /home/kali/forensic_utils.sh

root_system=$(get_boot_disk_name)

if [ -z "$root_system" ]
then
    root_system='null'
fi

# faz a busca e seta os discos reconhecidos como somente leitura
while read line ; do
    disk=`echo "$line" | awk '{print $1}'`
    if ! echo "$disk" | grep -q "$root_system"
    then           
       sudo blockdev --setro /dev/$disk
    else
       sudo blockdev --setrw /dev/$disk
    fi
done <<< "$(lsblk -l | grep 'part\|disk\|rom')"






