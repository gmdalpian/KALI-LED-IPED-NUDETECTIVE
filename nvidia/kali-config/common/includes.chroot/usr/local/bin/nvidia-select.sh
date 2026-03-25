#!/bin/bash

LOG="/var/log/nvidia-select.log"
KERNEL=$(uname -r)

echo "[+] ===== NVIDIA AUTO SELECT =====" >> $LOG
date >> $LOG

# =========================
# VERIFICAR MODO SEGURO (BOOT PARAM)
# =========================
if grep -q "nonvidia" /proc/cmdline; then
    echo "[+] Parâmetro 'nonvidia' detectado → ignorando drivers NVIDIA (Modo Seguro)" >> $LOG
    exit 0
fi

# =========================
# DETECÇÃO (SCRIPT EXTERNO)
# =========================
eval $(/usr/local/bin/gpu-detect.sh)

echo "[+] Vendor: $VENDOR" >> $LOG
echo "[+] PCI ID: $PCI_ID" >> $LOG
echo "[+] Arquitetura: $ARCH" >> $LOG
echo "[+] Driver recomendado: $DRIVER" >> $LOG

# =========================
# SEM NVIDIA → SAIR
# =========================
if [ "$VENDOR" != "NVIDIA" ]; then
    echo "[+] Sistema sem NVIDIA → mantendo drivers padrão" >> $LOG
    exit 0
fi

# =========================
# FUNÇÃO SEGURA DE LOAD
# =========================
load_driver_safe() {
    TYPE=$1
    BASE="/opt/nvidia/$TYPE"

    echo "[+] Tentando driver: $TYPE" >> $LOG

    if [ ! -d "$BASE" ]; then
        echo "[!] Diretório não encontrado: $BASE" >> $LOG
        return 1
    fi

    # Limpar bind anterior
    umount /lib/modules/$KERNEL/kernel/drivers/video 2>/dev/null || true

    # Bind mount (instantâneo)
    mount --bind "$BASE" /lib/modules/$KERNEL/kernel/drivers/video

    # Carregar módulo com proteção
    if timeout 30 modprobe nvidia; then
        echo "[+] nvidia carregado" >> $LOG

        timeout 30 modprobe nvidia_drm modeset=1 || true

        if timeout 3 nvidia-smi > /dev/null 2>&1; then
            echo "[+] Driver $TYPE OK" >> $LOG
            return 0
        fi
    fi

    echo "[!] Falha no driver $TYPE" >> $LOG

    modprobe -r nvidia 2>/dev/null || true
    umount /lib/modules/$KERNEL/kernel/drivers/video 2>/dev/null || true

    return 1
}

# =========================
# SELEÇÃO + FALLBACK
# =========================
case "$DRIVER" in

    open)
        echo "[+] Estratégia: OPEN → LEGACY → NOUVEAU" >> $LOG

        load_driver_safe open || \
        load_driver_safe legacy || \
        echo "[!] Fallback final: nouveau" >> $LOG
        ;;

    legacy)
        echo "[+] Estratégia: LEGACY → OPEN → NOUVEAU" >> $LOG

        load_driver_safe legacy || \
        load_driver_safe open || \
        echo "[!] Fallback final: nouveau" >> $LOG
        ;;

    *)
        echo "[!] Driver desconhecido → fallback seguro" >> $LOG

        load_driver_safe open || \
        load_driver_safe legacy || \
        echo "[!] Fallback final: nouveau" >> $LOG
        ;;
esac

echo "[+] ===== FINAL =====" >> $LOG
