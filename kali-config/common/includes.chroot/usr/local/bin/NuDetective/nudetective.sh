#!/bin/bash

/home/kali/mount_disks.sh

# Executa mplayer a primeira vez para corrigir bug de deteccao
sudo mplayer

# Executa NuDetective para Linux
sudo java -Xms1G -Xmx4G -jar /usr/local/bin/NuDetective/GUIMain2.jar NuDe40 ptBR
exit
