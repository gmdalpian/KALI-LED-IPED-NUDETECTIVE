#!/bin/bash

# monta os discos em /media/kali, com excecao do sistema em si

root_system=`cat /proc/mounts | grep /run/live/medium | awk '{print $1}'`

#remove o /dev/ e tambem o ultimo digito
root_system=${root_system:5:${#root_system}-6}

if [ -z "$root_system" ]
then
    root_system='null'
fi

# faz a busca e monta os discos reconhecidos como somente leitura
echo "Monta automaticamente as unidades reconhecidas como somente leitura"
while read line ; do
        disk=`echo "$line" | awk '{print $1}'`
        if ! echo "$disk" | grep -q "$root_system"
        then           
           sudo mkdir /media/$disk
           sudo mount -o ro /dev/$disk /media/$disk
        fi
done <<< "$(lsblk -l | grep 'part\|disk\|rom')"

# monta as unidades RAID do windows reconhecidas
echo "Tenta montar as unidades RAID do Windows, caso houver"
sudo ldmtool create all
sleep 2

while read line ; do
	if [[ ! -z $line ]]
	then
	        ldmdisk=`echo "$line" | awk '{print $1}'`
        	sudo mkdir /media/$ldmdisk
	        sudo mount -o ro /dev/mapper/$ldmdisk /media/$ldmdisk
	fi
done <<< "$(lsblk -l | grep '\dm\b')"

# busca e tenta montar as particoes bitlocker automaticamente
echo "Tenta montar as unidades bitlocker do Windows, caso a criptografia bitlocker esteja suspensa"
while read line ; do
	if [ ! -z "$line" ]
	then
		disk=`basename "$line"`
		if ! echo "$disk" | grep -q "$root_system"
		then
			echo "detected bitlocker in /dev/"$disk
			sudo mkdir /dislocker
			sudo mkdir /dislocker/bitlocker_$disk
			sudo mkdir /media/decrypted_$disk		
			sudo dislocker -V /dev/$disk -- /dislocker/bitlocker_$disk -r
			if sudo test -f /dislocker/bitlocker_$disk/dislocker-file;
			then
				sudo mount -o loop,ro /dislocker/bitlocker_$disk/dislocker-file /media/decrypted_$disk -t ntfs
			else
				while true; do
					bitlocker_pass=$(zenity --entry --title="Detectado BitLocker!" --text="Detectou-se uma particao criptografada com bitlocker em /dev/$disk, \nporem nao foi possivel decripta-la automaticamente. \nEste script tentara montar as demais particoes, caso houver. \nCaso se tenha a chave de recuperacao, digite-a abaixo, com os numeros separados por hifens:" --entry-text "ChaveDeRecuperacao" --width=500)
					if [ $? = 0 ]
					then 
						sudo dislocker -V /dev/$disk -p$bitlocker_pass -- /dislocker/bitlocker_$disk -r
						if sudo test -f /dislocker/bitlocker_$disk/dislocker-file;
						then
							sudo mount -o loop,ro /dislocker/bitlocker_$disk/dislocker-file /media/decrypted_$disk -t ntfs
							break
						else
							zenity --error --title="Erro de Chave BitLocker!" --text="A chave fornecida nao decifrou a unidade." --width=300 --timeout=20
						fi
					else
						break
					fi				
				done
			fi
		fi
	fi
done <<< "$(sudo dislocker-find)"