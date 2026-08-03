#!/bin/bash

export TEXTDOMAIN="cria_arquivo_memoria_swap"
export TEXTDOMAINDIR="/usr/share/locale"

source /usr/local/bin/forensic_utils.sh

triage=$(get_triage_device)

# Executa o IPED
if [ -z "$triage" ]
then
    echo "$(gettext "Could not locate triage partition")"
    
    zenity_title=$(gettext "Error creating memory!")
    zenity_text=$(gettext "In order to create the virtual memory file, the disk containing Kali must have a partition named IPED-TRIAGE, in exFAT format.")
    zenity --error --title="$zenity_title" --text="$zenity_text" --width=300 --timeout=20 2>/dev/null
else
    printf "$(gettext "Located triage partition at /dev/%s")\n" "$triage"

    mkdir -p /home/kali/Desktop/triage
    sudo mount -o rw,uid=1000,gid=1000 /dev/$triage /home/kali/Desktop/triage
   
    zenity_title=$(gettext "Select Swap Memory Size")
    # Utilizando o padrão ANSI-C ($'') para a quebra de linha funcionar perfeitamente com o gettext
    zenity_text=$(gettext $'Select the desired size for the memory file to be created, in GB.\nA minimum of 4 is recommended.')
    
    mem_size=$(zenity --entry --title="$zenity_title" --text="$zenity_text" --entry-text "4" --width=500 2>/dev/null)
    
    if [ $? = 0 ]
    then
        echo "$(gettext "Creating swap virtual memory file...")"
        truncate -s "$mem_size"G /home/kali/Desktop/triage/swapfile
        sudo mkswap /home/kali/Desktop/triage/swapfile
        sudo swapon /home/kali/Desktop/triage/swapfile   
    fi
    
    if [[ -n $(swapon -s) ]]; then
         zenity_info=$(gettext "Memory file enabled!")
    	 zenity --info --text="$zenity_info" 2>/dev/null
    else
         zenity_err=$(gettext "Error creating memory file!")
       	 zenity --info --text="$zenity_err" 2>/dev/null
    fi
fi