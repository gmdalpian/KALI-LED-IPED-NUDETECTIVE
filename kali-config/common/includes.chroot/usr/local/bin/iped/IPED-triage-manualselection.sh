#!/bin/bash

/home/kali/mount_disks.sh

echo "Checando se o binario zenity esta instalado..."
zenitybin=`which zenity` 

if [ -z $zenitybin ]
then
   echo "Zenity nao instalado... Abortando..."
   exit 1
fi
echo "Zenity encontrado no caminho $zenitybin"

echo "Gerando e exibindo a lista de particoes/discos encontrados"
root_system=`cat /proc/mounts | grep /run/live/medium | awk '{print $1}'`
#remove o /dev/ e tambem o ultimo digito
root_system=${root_system:5:${#root_system}-6}

if [ -z "$root_system" ]
then
    root_system='null'
fi

# faz a busca e monta os discos reconhecidos como somente leitura
rm /tmp/lsblk_output.txt
while read line ; do
        if ! echo "$line" | grep -q "$root_system"
        then
           if ! (echo "$line" | grep -q "/run/live/medium") && ! (echo "$line" | grep -q "/rootfs/filesystem.squashfs")
           then   
               echo "$line" >> /tmp/lsblk_output.txt
           fi
        fi
done <<< "$(lsblk -l)"

sudo zenity --text-info --title="Lista de Particoes Encontradas" --filename=/tmp/lsblk_output.txt --width=800 --height=500 --font=courier

echo "Selecionando evidencia a ser processada..."
inputDir=`$zenitybin --file-selection --directory --title="Escolha o que deseja processar" --filename=/media/`

if [ -z $inputDir ]
then
   echo "Nada a ser processado... Abortando."
   exit 2
fi

echo "$inputDir foi selecionado para ser processado..."

# Executa mplayer a primeira vez para corrigir bug de deteccao
sudo mplayer

cd /usr/local/bin/iped/

diskstoprocess=" -d $inputDir"

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



