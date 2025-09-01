#!/bin/bash

/home/kali/mount_disks.sh

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

# Executa o IPED
if [ -z "$triage" ]
then
    echo "Nao localizou particao triage"
        zenity --error --title="Nao localizou particao Triage!" --text="Para que seja executado corretamente este aplicativo, e necessario que no disco contendo o Kali haja uma particao denominada IPED-TRIAGE, no formato exFAT, conforme manual de uso." --width=300 --timeout=20
else
    echo "Localizou a particao triage em /dev/$triage"
            
    # verifica se o diretorio triage ja existe e se foi montado
    if findmnt --mountpoint /home/kali/Desktop/triage &> /dev/null; then
        echo "Particao triage ja montada em /home/kali/Desktop/triage"
    else        
        echo "Criando particao triage"
        mkdir /home/kali/Desktop/triage
        sudo mount -o rw /dev/$triage /home/kali/Desktop/triage
    fi
        
    # verificar se a memoria swap ja foi habilitada
    num_linhas=$(cat /proc/swaps | wc -l)
    if [ "$num_linhas" -gt 1 ]; then   
        echo "Memoria SWAP ja esta habilitada"
        swapon --show    	 	
    else
	echo "Criando arquivo de memoria virtual swap..."
        sudo truncate -s 10G /home/kali/Desktop/triage/swapfile
        sudo mkswap /home/kali/Desktop/triage/swapfile
        sudo swapon /home/kali/Desktop/triage/swapfile 
    fi
	
	sudo rm -rf /home/kali/Desktop/triage/IPED-CASO/

	sudo mkdir /home/kali/Desktop/triage/IPED-CASO/
	
	cmdline_triage="sudo java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped.jar -o /home/kali/Desktop/triage/IPED-CASO/ -profile csam_triage -log /home/kali/Desktop/triage/IPED-Processamento-$(date +%y%m%d%H%M).log -d /media/"
	
   	if sudo test -f /home/kali/Desktop/triage/palavras-chave.txt;  
	then
	    cmdline_triage+=" -l /home/kali/Desktop/triage/palavras-chave.txt"
	fi	
	
	# seta as configuracoes locais do IPED para o pendrive triagem
	sudo cp LocalConfig-triage.txt LocalConfig.txt
	
	$cmdline_triage
	
	sudo cp Ferramenta_de_Pesquisa.sh /home/kali/Desktop/triage/IPED-CASO/
	cp "IPED-Caso-triage.desktop" /home/kali/Desktop/IPED-Caso.desktop
	
	cd /home/kali/Desktop/triage/IPED-CASO/

	./Ferramenta_de_Pesquisa.sh
fi



