#!/bin/bash
# Sets disks to read-only using the blockdev command

LOG_FILE="/var/log/forensic-ro.log"

# --- Função de Logging Avançada ---
log() {
    local MSG="[Forensic-RO] $1"
    # Grava no arquivo de log com timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S') $MSG" >> "$LOG_FILE"
    # Envia para o buffer do kernel (dmesg / console de boot)
    echo "$MSG" > /dev/kmsg
}

log "===== STARTING FORENSIC DISK WRITE-PROTECTION ====="

# 1. Verificações Iniciais
if [ ! -f "/usr/local/bin/forensic_utils.sh" ]; then
    log "CRITICAL ERROR: /usr/local/bin/forensic_utils.sh not found. Exiting."
    exit 1
fi

source /usr/local/bin/forensic_utils.sh

log "[Step 1/4] Identifying boot disk..."
root_system=$(get_boot_disk_name)

if [ -z "$root_system" ]; then
    log "WARNING: Could not identify boot disk. root_system is empty."
    root_system='null'
    boot_components=""
else
    log "Boot disk identified as: $root_system"
    boot_components=$(lsblk -n -r -o KNAME "/dev/$root_system" 2>/dev/null)
    components_inline=$(echo "$boot_components" | tr '\n' ' ')
    log "Boot components excluded from locking: $components_inline"
fi

log "[Step 2/4] Scanning for Windows Dynamic Disks (LDM)..."
# Redireciona a saída do ldmtool para o arquivo de log para facilitar o debug
sudo ldmtool create all >> "$LOG_FILE" 2>&1 || true

log "[Step 3/4] Waiting for udev to settle..."
# Adicionado um timeout de segurança semelhante ao modelo NVIDIA
sudo udevadm settle timeout=10 || true
log "Udev settled. Proceeding to apply blockdev rules."

log "[Step 4/4] Applying read-only rules to recognized disks..."
while read -r line ; do
    disk=$(echo "$line" | awk '{print $1}')

    if ! echo "$boot_components" | grep -w -q "$disk"; then
       log "-> Locking device (RO): /dev/$disk"
       sudo blockdev --setro "/dev/$disk" >> "$LOG_FILE" 2>&1
    else
       log "-> Skipping boot device, setting (RW): /dev/$disk"
       sudo blockdev --setrw "/dev/$disk" >> "$LOG_FILE" 2>&1
    fi
done <<< "$(lsblk -l -n -o KNAME,TYPE | grep -iE 'part|disk|rom|dm|ldm')"

# [Keep your existing code above...]

log "===== FORENSIC DISK WRITE-PROTECTION COMPLETED SUCCESSFULLY ====="

# Create a flag file in RAM to signal udev that boot initialization is done
touch /run/forensic_boot_done

exit 0