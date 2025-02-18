#!/bin/bash

# Executa mplayer a primeira vez para corrigir bug de deteccao
sudo mplayer

cd /usr/local/bin/iped/

diskstoprocess=""

root_system=`cat /proc/mounts | grep /run/live/medium | awk '{print $1}'`

# verifica se ha outras particoes no disco usado como boot e se alguma delas denomina-se 'IPED-TRIAGE', e salva na variavel $triage
root_system_triage=${root_system:5:${#root_system}-6}

if [ -z "$root_system_triage" ]
then
    root_system_triage='null'
fi

while read line ; do
        part=`echo "$line" | awk '{print $1}'`
        if echo "$part" | grep -q "$root_system_triage"
        then      
           if sudo blkid /dev/$part | grep 'IPED-TRIAGE'
	   then
	       triage=$part
	   fi
        fi
done <<< "$(lsblk -l | grep part)"

# faz a busca e adiciona os discos reconhecidos
while read line ; do
        disk=`echo "$line" | awk '{print $1}'`
        if ! echo "$root_system" | grep -q "$disk"
        then
          diskstoprocess+=" -d /dev/$disk"
        fi
done <<< "$(lsblk -l | grep disk)"

# faz a busca e adiciona as imagens RAID Windows
sudo ldmtool create all
while read line ; do
        disk=`echo "$line" | awk '{print $1}'`
        if ! echo "$diskstoprocess" | grep -q "$disk"
        then
          diskstoprocess+=" -d /dev/mapper/$disk"
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
				diskstoprocess+=" -d /dislocker/dislocker-file_$disk.dd"
			else
				while true; do
					#pega as informacoes do bitlocker e salva na variavel BITLOCKER_INFO
					BITLOCKER_INFO=('', '')
					while read line ; do
						if [[ ! -z $line ]]
						then
							if [[ $line =~ "Description:" ]]; then
								BITLOCKER_INFO[0]=$line
							fi
							if [[ $line =~ "VMK protected with recovery passphrase" ]]; then
								BITLOCKER_INFO[1]=${previousline^^}
							fi
							previousline=$line;
						fi
					done <<< "$(sudo cryptsetup bitlkDump /dev/$disk)"
					
					recovery_key_id=`sudo dislocker-metadata -V /dev/$disk | grep 'Recovery Key' | head -n 1 | awk '{print $NF}'`
					
					bitlocker_pass=$(zenity --entry --title="Detectado BitLocker!" --text="Detectou-se uma particao criptografada com bitlocker em /dev/$disk, \nporem nao foi possivel decripta-la automaticamente. \nEste script tentara montar as demais particoes, se existirem. \nCaso se tenha a chave de recuperacao, digite-a abaixo, com os numeros separados por hifens: \n${BITLOCKER_INFO[0]} \n${BITLOCKER_INFO[1]}" --entry-text "ChaveDeRecuperacao" --width=500)
					
					if [ $? = 0 ]
					then 				    					
						sudo dislocker -V /dev/$disk -p$bitlocker_pass -- /dislocker/bitlocker_$disk -r
						if sudo test -f /dislocker/bitlocker_$disk/dislocker-file;
						then
							sudo ln -s /dislocker/bitlocker_$disk/dislocker-file /dislocker/dislocker-file_$disk.dd
							diskstoprocess+=" -d /dislocker/dislocker-file_$disk.dd"
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

# Executa o IPED
if [ -z "$triage" ]
then
    echo "Nao localizou particao triage"
		
    sudo rm -rf /home/kali/Desktop/IPED-CASO/

    mkdir /home/kali/Desktop/IPED-CASO/		

	cmdline="sudo java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped.jar -o /home/kali/Desktop/IPED-CASO/ -profile triage -l /usr/local/bin/iped/palavras-chave.txt"
	
	$cmdline $diskstoprocess

	cp Ferramenta_de_Pesquisa.sh /home/kali/Desktop/IPED-CASO/
	cp "IPED-Caso.desktop" /home/kali/Desktop/

	cd /home/kali/Desktop/IPED-CASO/

	./Ferramenta_de_Pesquisa.sh
else
    echo "Localizou a particao triage em /dev/$triage"
	mkdir /home/kali/Desktop/triage
	sudo mount -o rw /dev/$triage /home/kali/Desktop/triage
	
	sudo rm -rf /home/kali/Desktop/triage/IPED-CASO/

	sudo mkdir /home/kali/Desktop/triage/IPED-CASO/
	
	cmdline_triage="sudo java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped.jar -o /home/kali/Desktop/triage/IPED-CASO/ -profile triage -log /home/kali/Desktop/triage/IPED-Processamento-$(date +%y%m%d%H%M).log"
	
   	if sudo test -f /home/kali/Desktop/triage/palavras-chave.txt;  
	then
	    cmdline_triage+=" -l /home/kali/Desktop/triage/palavras-chave.txt"
	fi	
	
	# seta as configuracoes locais do IPED para o pendrive triagem
	sudo cp LocalConfig-triage.txt LocalConfig.txt
	
	$cmdline_triage $diskstoprocess
	
	sudo cp Ferramenta_de_Pesquisa.sh /home/kali/Desktop/triage/IPED-CASO/
	cp "IPED-Caso-triage.desktop" /home/kali/Desktop/IPED-Caso.desktop
	
	cd /home/kali/Desktop/triage/IPED-CASO/

	./Ferramenta_de_Pesquisa.sh
fi



