#!/bin/bash
# forensic_utils.sh - Biblioteca central para detecção de dispositivos de boot e triage

# Retorna o caminho físico da partição de boot (ex: /dev/sda1)
get_boot_phys_part() {
    local boot_dev=$(findmnt -n -o SOURCE /run/live/medium)
    if [[ "$boot_dev" == *"/mapper/ventoy"* ]]; then
        local map_id=$(sudo dmsetup table ventoy 2>/dev/null | awk '{print $4}')
        readlink -f "/sys/dev/block/$map_id"
    else
        echo "$boot_dev"
    fi
}

# Retorna apenas o nome do disco pai do boot (ex: sda ou nvme0n1)
get_boot_disk_name() {
    local phys_part=$(get_boot_phys_part)
    local disk_name=$(lsblk -no pkname "$phys_part")
    [ -z "$disk_name" ] && basename "$phys_part" || echo "$disk_name"
}

# Retorna o dispositivo correto para montagem do IPED-TRIAGE (resolve dm-X)
get_triage_device() {
    local root_disk=$(get_boot_disk_name)
    local triage_dev=""
    local found=false

    while read -r part_name ; do
        local current_phys="/dev/$part_name"
        if sudo blkid "$current_phys" | grep -q 'IPED-TRIAGE'; then
            # Se houver mapeamentos (Ventoy), valida qual DM tem o label
            local holders_dir="/sys/class/block/$part_name/holders"
            if [ -d "$holders_dir" ] && [ "$(ls -A "$holders_dir")" ]; then
                for holder in $(ls "$holders_dir"); do
                    if sudo blkid "/dev/$holder" | grep -q 'IPED-TRIAGE'; then
                        triage_dev="/dev/$holder"
                        found=true; break
                    fi
                done
            fi
            # Se não achou via holder, usa o físico
            if ! $found; then triage_dev="$current_phys"; found=true; fi
            # Prioriza se estiver no disco de boot
            [[ "$part_name" == *"$root_disk"* ]] && break
        fi
    done <<< "$(lsblk -lno NAME,TYPE | grep part | awk '{print $1}')"
    echo "$triage_dev"
}

# Caso o script seja chamado diretamente via terminal para testes:
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        --boot-phys) get_boot_phys_part ;;
        --boot-disk) get_boot_disk_name ;;
        --triage-dev) get_triage_device ;;
        *) echo "Uso: $0 [--boot-phys | --boot-disk | --triage-dev]" ;;
    esac
fi