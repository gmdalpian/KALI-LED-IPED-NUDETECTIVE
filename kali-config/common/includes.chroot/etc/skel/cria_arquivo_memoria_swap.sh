#!/bin/bash

source /home/kali/forensic_utils.sh

triage=$(get_triage_device)

# Executa o IPED
if [ -z "$triage" ]
then
    echo "Nao localizou particao triage"
    zenity --error --title="Erro ao criar memoria!" --text="Para que seja criado o arquivo de memoria virtual, e necessario que no disco contendo o Kali haja uma particao denominada IPED-TRIAGE, no formato exFAT." --width=300 --timeout=20
else
    echo "Localizou a particao triage em /dev/$triage"

    mkdir /home/kali/Desktop/triage
    sudo mount -o rw /dev/$triage /home/kali/Desktop/triage
   
    mem_size=$(zenity --entry --title="Selecione o Tamanho da Memoria Swap" --text="Selecione o tamanho desejado para o arquivo de memoria a ser criado, em GB. \nRecomenda-se no minimo 4." --entry-text "4" --width=500)
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
       	 zenity --info --text="Erro ao criar arquivo de memoria!"
    fi
fi
