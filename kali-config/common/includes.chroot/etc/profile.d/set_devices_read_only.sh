# seta os discos como somente leitura pelo comando blockdev

root_system=`cat /proc/mounts | grep /run/live/medium | awk '{print $1}'`

#remove o /dev/ e tambem o ultimo digito
root_system=${root_system:5:${#root_system}-6}

if [ -z "$root_system" ]
then
    root_system='null'
fi

# faz a busca e seta os discos reconhecidos como somente leitura
while read line ; do
        disk=`echo "$line" | awk '{print $1}'`
        if ! echo "$disk" | grep -q "$root_system"
        then           
           sudo blockdev --setro /dev/$disk
        fi
done <<< "$(lsblk -l | grep 'disk')"






