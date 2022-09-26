#!/bin/bash

# Executa mplayer a primeira vez para corrigir bug de deteccao
sudo mplayer

sudo rm -rf /home/kali/Desktop/IPED-CASO/

mkdir /home/kali/Desktop/IPED-CASO/

cd /usr/local/bin/iped/

cmdline="sudo PATH=/usr/local/bin/sleuthkit-4.11.1_iped_patch/bin/:$PATH java -jar iped.jar -o /home/kali/Desktop/IPED-CASO/ -l /usr/local/bin/iped/palavras-chave.txt"

root_system=`cat /proc/mounts | grep /run/live/medium | awk '{print $1}'`

# faz a busca e adiciona os discos reconhecidos
while read line ; do
        disk=`echo "$line" | awk '{print $1}'`
        if ! echo "$root_system" | grep -q "$disk"
        then
          cmdline+=" -d /dev/$disk"
        fi
done <<< "$(lsblk -l | grep disk)"

# faz a busca e adiciona as imagens RAID Windows
sudo ldmtool create all
while read line ; do
        disk=`echo "$line" | awk '{print $1}'`
        if ! echo "$cmdline" | grep -q "$disk"
        then
          cmdline+=" -d /dev/mapper/$disk"
        fi
done <<< "$(lsblk -l | grep '\dm\b')"

# busca e tenta montar as particoes bitlocker automaticamente
echo "Tenta montar as unidades bitlocker do Windows"
while read line ; do
	if [ ! -z "$line" ]
	then
	       	disk=`basename "$line"`
        	if ! echo "$disk" | grep -q "$root_system"
	        then           
			echo "detected bitlocker in /dev/"$disk
			sudo mkdir /dislocker
			sudo mkdir /dislocker/bitlocker_$disk
		
			sudo dislocker -V /dev/$disk -- /dislocker/bitlocker_$disk -r
			if sudo test -f /dislocker/bitlocker_$disk/dislocker-file;
			then
				sudo ln -s /dislocker/bitlocker_$disk/dislocker-file /dislocker/dislocker-file_$disk.dd
				cmdline+=" -d /dislocker/dislocker-file_$disk.dd"
			else
				while true; do
					bitlocker_pass=$(zenity --entry --title="Detectado BitLocker!" --text="Detectou-se uma particao criptografada com bitlocker em /dev/$disk, \nporem nao foi possivel decripta-la automaticamente. \nEste script tentara montar as demais particoes, caso houver. \nCaso se tenha a chave de recuperacao, digite-a abaixo, com os numeros separados por hifens:" --entry-text "ChaveDeRecuperacao" --width=500)
					if [ $? = 0 ]
					then 				    					
						sudo dislocker -V /dev/$disk -p$bitlocker_pass -- /dislocker/bitlocker_$disk -r
						if sudo test -f /dislocker/bitlocker_$disk/dislocker-file;
						then
							sudo ln -s /dislocker/bitlocker_$disk/dislocker-file /dislocker/dislocker-file_$disk.dd
							cmdline+=" -d /dislocker/dislocker-file_$disk.dd"
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

$cmdline

cp Ferramenta_de_Pesquisa.sh /home/kali/Desktop/IPED-CASO/
cp "IPED-Caso.desktop" /home/kali/Desktop/

cd /home/kali/Desktop/IPED-CASO/

./Ferramenta_de_Pesquisa.sh



