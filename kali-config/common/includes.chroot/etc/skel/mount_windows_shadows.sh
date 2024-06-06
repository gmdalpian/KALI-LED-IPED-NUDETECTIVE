#!/bin/bash

/home/kali/mount_disks.sh

root_system=`cat /proc/mounts | grep /run/live/medium | awk '{print $1}'`

#remove o /dev/ e tambem o ultimo digito
root_system=${root_system:5:${#root_system}-6}

if [ -z "$root_system" ]
then
    root_system='null'
fi

# busca e tenta montar as Volume Shadow Copy (VSS) do Windows
echo "Tenta montar as Volume Shadow Copy (VSS) do Windows, caso existam"

hasVSS="false"

while read line ; do
    disk=`echo "$line" | awk '{print $1}'`
    if ! echo "$disk" | grep -q "$root_system"
    then  
		if sudo vshadowinfo /dev/$disk
		then
			echo "Encontrou VSS na particao $disk"
			zenity --info --text="Encontrou VSS na particao $disk"
			hasVSS="true"
			sudo mkdir /vss
			sudo mkdir /vss/vss_$disk
			sudo vshadowmount /dev/$disk /vss/vss_$disk
			sudo mkdir /media/vss_$disk
			for vss in $(sudo ls /vss/vss_$disk); do
				sudo mkdir /media/vss_$disk/$vss
				sudo mount -o ro /vss/vss_$disk/$vss /media/vss_$disk/$vss
			done			
		fi
    fi
done <<< "$(lsblk -l | grep 'part\|disk')"

# busca e tenta montar as Volume Shadow Copy (VSS) do Windows para particoes bitlocker ja decriptografadas
for dislockerpart in $(sudo ls /dislocker); do
	if sudo vshadowinfo /dislocker/$dislockerpart/dislocker-file
	then
		echo "Encontrou VSS na particao bitlocker $dislockerpart"
		zenity --info --text="Encontrou VSS na particao $dislockerpart"
		hasVSS="true"
		sudo mkdir /vss
		sudo mkdir /vss/vss_$dislockerpart
		sudo vshadowmount /dislocker/$dislockerpart/dislocker-file /vss/vss_$dislockerpart
		sudo mkdir /media/vss_$dislockerpart
		for vss in $(sudo ls /vss/vss_$dislockerpart); do
			sudo mkdir /media/vss_$dislockerpart/$vss
			sudo mount -o ro /vss/vss_$dislockerpart/$vss /media/vss_$dislockerpart/$vss
		done			
	fi
done	

if [[ "$hasVSS" == "false" ]]
then
  zenity --info --text="Nao foram localizadas copias de sombra VSS"
fi
