#!/bin/bash

/home/kali/mount_disks.sh

# Executa mplayer a primeira vez para corrigir bug de deteccao
sudo mplayer

sudo LD_LIBRARY_PATH=/usr/lib/jvm/java-11-openjdk-amd64/lib/:$LD_LIBRARY_PATH java -Xmx1500M -jar /usr/local/bin/LED/led.jar /media/
