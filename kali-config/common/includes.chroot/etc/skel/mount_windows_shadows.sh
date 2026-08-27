#!/bin/bash

export TEXTDOMAIN="mount_windows_shadows"
export TEXTDOMAINDIR="/usr/share/locale"

source /usr/local/bin/forensic_utils.sh

/home/kali/mount_disks.sh

MEDIA_DIR="/run/media"

root_system=$(get_boot_disk_name)

# busca e tenta montar as Volume Shadow Copy (VSS) do Windows
echo "$(gettext "Trying to mount Windows Volume Shadow Copies (VSS), if any exist")"

hasVSS="false"

while read line ; do
    disk=`echo "$line" | awk '{print $1}'`
    if ! echo "$disk" | grep -q "$root_system"
    then  
		if sudo vshadowinfo /dev/$disk >/dev/null 2>&1
		then
			printf "$(gettext "Found VSS on partition %s")\n" "$disk"
			zenity_text=$(printf "$(gettext "Found VSS on partition %s")" "$disk")
			zenity --info --text="$zenity_text" 2>/dev/null
			
			hasVSS="true"
			sudo mkdir -p /vss
			sudo mkdir -p /vss/vss_$disk
			sudo vshadowmount /dev/$disk /vss/vss_$disk
			sudo mkdir -p $MEDIA_DIR/vss_$disk
			for vss in $(sudo ls /vss/vss_$disk); do
				sudo mkdir -p $MEDIA_DIR/vss_$disk/$vss
				sudo mount -t ntfs -o ro /vss/vss_$disk/$vss $MEDIA_DIR/vss_$disk/$vss
			done			
		fi
    fi
done <<< "$(lsblk -l | grep 'part\|disk')"

# busca e tenta montar as Volume Shadow Copy (VSS) do Windows para particoes bitlocker ja decriptografadas
for dislockerpart in $(sudo ls /dislocker 2>/dev/null); do
	if sudo vshadowinfo /dislocker/$dislockerpart/dislocker-file >/dev/null 2>&1
	then
		printf "$(gettext "Found VSS on BitLocker partition %s")\n" "$dislockerpart"
		zenity_text=$(printf "$(gettext "Found VSS on BitLocker partition %s")" "$dislockerpart")
		zenity --info --text="$zenity_text" 2>/dev/null
		
		hasVSS="true"
		sudo mkdir -p /vss
		sudo mkdir -p /vss/vss_$dislockerpart
		sudo vshadowmount /dislocker/$dislockerpart/dislocker-file /vss/vss_$dislockerpart
		sudo mkdir -p $MEDIA_DIR/vss_$dislockerpart
		for vss in $(sudo ls /vss/vss_$dislockerpart); do
			sudo mkdir -p $MEDIA_DIR/vss_$dislockerpart/$vss
			sudo mount -t ntfs -o ro /vss/vss_$dislockerpart/$vss $MEDIA_DIR/vss_$dislockerpart/$vss
		done			
	fi
done	

if [[ "$hasVSS" == "false" ]]
then
    zenity_info=$(gettext "No VSS shadow copies were found")
    zenity --info --text="$zenity_info" 2>/dev/null
fi