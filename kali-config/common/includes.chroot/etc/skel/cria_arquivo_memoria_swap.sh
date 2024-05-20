#!/bin/bash

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
           if sudo blkid /dev/$part | grep 'IPED-TRIAGE.*exfat'
	   then
	       triage=$part
	   fi
        fi
done <<< "$(lsblk -l | grep part)"

# Executa o IPED
if [ -z "$triage" ]
then
    echo "Nao localizou particao triage"
    zenity --error --title="Erro ao criar memoria!" --text="Para que seja criado o arquivo de memoria virtual, e necessario que no disco contendo o Kali haja uma particao denominada IPED-TRIAGE, no formato exFAT." --width=300 --timeout=20
else
    echo "Localizou a particao triage em /dev/$triage"

    mkdir /home/kali/Desktop/triage
    sudo mount -o rw /dev/$triage /home/kali/Desktop/triage
   
    mem_size=$(zenity --entry --title="Selecione o Tamanho da Memoria Swap" --text="Selecione o tamanho desejado para o arquivo de memoria a ser criado, em GB. \nRecomenda-se no minimo 4. Como o arquivo deve ser preenchido por zeros, \nesta operacao podera durar alguns minutos." --entry-text "4" --width=500)
    if [ $? = 0 ]
    then
        echo "Criando arquivo de memoria virtual swap..."
        sudo truncate -s "$mem_size"G /home/kali/Desktop/triage/swapfile
        sudo mkswap /home/kali/Desktop/triage/swapfile
        sudo swapon /home/kali/Desktop/triage/swapfile   
    fi
    
    if [[ -n $(swapon -s) ]]; then
    	 zenity --info --text="Arquivo de memoria habilitado!"
    else
       	 zenity --info --text= "Erro ao criar arquivo de memoria!"
    fi
fi
