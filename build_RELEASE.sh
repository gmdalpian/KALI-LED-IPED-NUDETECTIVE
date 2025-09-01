#!/bin/bash

if [ -z "$1" ]
  then
    echo "Modo de uso: build_RELEASE.sh NUMERO_DA_VERSA0_KALI"
    exit
fi

RELEASE=$1
# Gera um novo iso e ja o copia para o disco de saida
echo 'Apaga arquivos'
sudo rm -rf kali-live

echo 'Baixa estrutura git'
#git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git
git clone https://gitlab.com/kalilinux/build-scripts/kali-live.git

echo 'Copia arquivos novos'
cp -Rf /media/kali/DISCO_EXTERNO/kali-config/* /home/kali/kali-live/kali-config/
if [ $? -eq 0 ]; then
    echo "File copied successfully."
else
    echo "File copy failed."
fi

cd /home/kali/kali-live/kali-config/common/includes.chroot/usr/local/bin
tar vzxf /media/kali/DISCO_EXTERNO/python/*

echo 'Gera o novo ISO'
cd /home/kali/kali-live
./build.sh --verbose --distribution kali-last-snapshot --version $RELEASE

md5sum /home/kali/kali-live/images/kali-linux-$RELEASE-live-amd64.iso > /home/kali/kali-live/images/kali-linux-$RELEASE-live-amd64.iso.md5

rm -rf /media/kali/DISCO_EXTERNO/images/*

echo 'Copia o novo iso para o disco externo'
cp /home/kali/kali-live/images/kali-linux-$RELEASE-live-amd64.iso /media/kali/DISCO_EXTERNO/images/KALI-LED-IPED-NUDETECTIVE-$(date -I).iso
cp /home/kali/kali-live/images/kali-linux-$RELEASE-live-amd64.iso.md5 /media/kali/DISCO_EXTERNO/images/KALI-LED-IPED-NUDETECTIVE-$(date -I).iso.md5
