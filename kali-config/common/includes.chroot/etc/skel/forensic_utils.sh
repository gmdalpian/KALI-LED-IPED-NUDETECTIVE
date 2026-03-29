#!/bin/bash
# forensic_utils.sh - Biblioteca central para detecção de dispositivos de boot e triage

# Retorna o caminho físico da partição de boot (ex: /dev/sdb1)
get_boot_phys_part() {
    local boot_dev=$(findmnt -n -o SOURCE /run/live/medium)
    
    # Verifica se o boot é via Device Mapper (Ventoy)
    if [[ "$boot_dev" == *"/mapper/ventoy"* ]]; then
        # ADIÇÃO: 'head -n 1' garante que pegaremos apenas o primeiro mapeamento
        # contornando a saída multilinha do modo GRUB2 do Ventoy
        local map_id=$(sudo dmsetup table ventoy 2>/dev/null | head -n 1 | awk '{print $4}')
        
        if [[ -n "$map_id" ]]; then
            local dev_name=$(basename "$(readlink -f "/sys/dev/block/$map_id")")
            echo "/dev/$dev_name"
        else
            echo "$boot_dev"
        fi
    else
        echo "$boot_dev"
    fi
}

# Retorna apenas o nome do disco pai do boot (ex: sdb)
get_boot_disk_name() {
    local phys_part=$(get_boot_phys_part)
    local disk_name=$(lsblk -no pkname "$phys_part" 2>/dev/null)
    
    if [[ -z "$disk_name" ]]; then
        basename "$phys_part"
    else
        echo "$disk_name"
    fi
}

# Retorna o dispositivo correto para montagem do IPED-TRIAGE (resolve dm-X)
get_triage_device() {
    local root_disk=$(get_boot_disk_name)
    local triage_dev=""
    local found=false

    while read -r part_name ; do
        local current_phys="/dev/$part_name"
        if sudo blkid "$current_phys" | grep -q 'IPED-TRIAGE'; then
            local holders_dir="/sys/class/block/$part_name/holders"
            if [ -d "$holders_dir" ] && [ "$(ls -A "$holders_dir")" ]; then
                for holder in $(ls "$holders_dir"); do
                    if sudo blkid "/dev/$holder" | grep -q 'IPED-TRIAGE'; then
                        triage_dev="/dev/$holder"
                        found=true; break
                    fi
                done
            fi
            if ! $found; then triage_dev="$current_phys"; found=true; fi
            [[ "$part_name" == *"$root_disk"* ]] && break
        fi
    done <<< "$(lsblk -lno NAME,TYPE | grep part | awk '{print $1}')"
    echo "$triage_dev"
}

# Interface de linha de comando para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        --boot-phys) get_boot_phys_part ;;
        --boot-disk) get_boot_disk_name ;;
        --triage-dev) get_triage_device ;;
        *) echo "Uso: $0 [--boot-phys | --boot-disk | --triage-dev]" ;;
    esac
fi