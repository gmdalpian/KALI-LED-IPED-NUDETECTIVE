#!/bin/bash

/home/kali/mount_disks.sh

# Executa mplayer a primeira vez para corrigir bug de deteccao
sudo mplayer

sudo rm -rf /home/kali/Desktop/IPED-CASO/

mkdir /home/kali/Desktop/IPED-CASO/

cd /usr/local/bin/iped/

sudo PATH=/usr/local/bin/sleuthkit-4.11.1_iped_patch/bin/:$PATH java -jar iped.jar -o /home/kali/Desktop/IPED-CASO/ -profile fastmode -d /media/ -l /usr/local/bin/iped/palavras-chave.txt

cp Ferramenta_de_Pesquisa.sh /home/kali/Desktop/IPED-CASO/
cp "IPED-Caso.desktop" /home/kali/Desktop/

cd /home/kali/Desktop/IPED-CASO/

./Ferramenta_de_Pesquisa.sh
