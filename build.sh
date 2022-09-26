#!/bin/bash

# Gera um novo iso e ja o copia para o disco de saida
echo 'Apaga arquivos'
sudo rm -rf live-build-config

echo 'Baixa estrutura git'
git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git

echo 'Copia arquivos novos'
cp -Rf /media/kali/DISCO_EXTERNO/kali-config/* /home/kali/live-build-config/kali-config/

echo 'Gera o novo ISO'
cd live-build-config
./build.sh --verbose

md5sum /home/kali/live-build-config/images/kali-linux-rolling-live-amd64.iso > /home/kali/live-build-config/images/kali-linux-rolling-live-amd64.iso.md5

rm -rf /media/kali/DISCO_EXTERNO/images/*

echo 'Copia o novo iso para o disco externo'
cp /home/kali/live-build-config/images/kali-linux-rolling-live-amd64.iso /media/kali/DISCO_EXTERNO/images/KALI-LED-IPED-NUDETECTIVE-$(date -I).iso
cp /home/kali/live-build-config/images/kali-linux-rolling-live-amd64.iso.md5 /media/kali/DISCO_EXTERNO/images/KALI-LED-IPED-NUDETECTIVE-$(date -I).iso.md5