#!/bin/bash

if [ -z "$1" ]
  then
    echo "Modo de uso: build_RELEASE.sh NUMERO_DA_VERSA0_KALI"
    exit
fi

RELEASE=$1
# Gera um novo iso e ja o copia para o disco de saida
echo 'Apaga arquivos'
sudo rm -rf live-build-config

echo 'Baixa estrutura git'
git clone https://gitlab.com/kalilinux/build-scripts/live-build-config.git

echo 'Copia arquivos novos'
cp -Rf /media/kali/DISCO_EXTERNO/kali-config/* /home/kali/live-build-config/kali-config/

echo 'Customizando versao comunidade'
rm -rf /home/kali/live-build-config/kali-config/common/includes.chroot/usr/local/bin/LED
rm -rf /home/kali/live-build-config/kali-config/common/includes.chroot/usr/local/bin/NuDetective
rm -rf '/home/kali/live-build-config/kali-config/common/includes.chroot/etc/skel/Desktop/LED - Escolher Midia.desktop'
rm -rf '/home/kali/live-build-config/kali-config/common/includes.chroot/etc/skel/Desktop/LED - Montar e Vasculhar.desktop'
rm -rf /home/kali/live-build-config/kali-config/common/includes.chroot/etc/skel/Desktop/Nudetective.desktop
cp -f /media/kali/DISCO_EXTERNO/kali-config/common/includes.chroot/etc/skel/Pictures/plano_de_fundo_kali1.jpg /home/kali/live-build-config/kali-config/common/includes.chroot/etc/skel/Pictures/plano_de_fundo.jpg


echo Gera o novo ISO --version $RELEASE
cd live-build-config
./build.sh --verbose --live --distribution kali-last-snapshot --version $RELEASE

md5sum /home/kali/live-build-config/images/kali-linux-$RELEASE-live-amd64.iso > /home/kali/live-build-config/images/kali-linux-$RELEASE-live-amd64.iso.md5

rm -rf /media/kali/DISCO_EXTERNO/images/*

echo 'Copia o novo iso para o disco externo'
cp /home/kali/live-build-config/images/kali-linux-$RELEASE-live-amd64.iso /media/kali/DISCO_EXTERNO/images/KALI-LED-IPED-NUDETECTIVE-$(date -I).iso
cp /home/kali/live-build-config/images/kali-linux-$RELEASE-live-amd64.iso.md5 /media/kali/DISCO_EXTERNO/images/KALI-LED-IPED-NUDETECTIVE-$(date -I).iso.md5
