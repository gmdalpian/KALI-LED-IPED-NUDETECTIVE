#!/bin/bash

# --- Função de Peso (Ranking) para Arquiteturas ---
# Quanto maior o número, mais moderna é a arquitetura.
get_rank() {
    case "$1" in
        blackwell) echo 7 ;;
        ada)       echo 6 ;;
        ampere)    echo 5 ;;
        turing)    echo 4 ;;
        volta)     echo 3 ;;
        pascal)    echo 2 ;;
        *)         echo 1 ;; # Unknown ou outras marcas
    esac
}

# --- Função de Identificação de Arquitetura NVIDIA ---
get_architecture() {
    PREFIX_HEX=$(echo "$1" | cut -c1-2)
    PREFIX=$((16#$PREFIX_HEX))

    if (( PREFIX >= 0x28 )); then
        echo "blackwell"
    elif (( PREFIX >= 0x26 && PREFIX <= 0x27 )); then
        echo "ada"
    elif (( PREFIX >= 0x22 && PREFIX <= 0x25 )); then
        echo "ampere"
    elif (( PREFIX >= 0x20 && PREFIX <= 0x21 )); then
        echo "turing"
    elif (( PREFIX == 0x1d )); then
        echo "volta"
    elif (( PREFIX >= 0x1b && PREFIX <= 0x1f )); then
        # Pascal (Garante que Volta 1D não caia aqui se vier depois)
        echo "pascal"
    else
        echo "unknown"
    fi
}

detect_best_gpu() {
    # Busca apenas classes de exibição (0300, 0302, 0380) para evitar lixo
    # O filtro -d ::0300 filtra pelo Class ID oficial do PCI
    GPUS_FOUND=$(lspci -nn -d ::0300 && lspci -nn -d ::0302 && lspci -nn -d ::0380)

    if [ -z "$GPUS_FOUND" ]; then
        echo "VENDOR=NONE"
        echo "DRIVER=none"
        return
    fi

    BEST_RANK=-1
    
    # Processa cada GPU encontrada
    while read -r line; do
        CURRENT_PCI_ID=$(echo "$line" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])')
        CURRENT_VENDOR_ID=$(echo "$CURRENT_PCI_ID" | cut -d: -f1)
        CURRENT_DEVICE_ID=$(echo "$CURRENT_PCI_ID" | cut -d: -f2)

        # Identifica Vendor
        case "$CURRENT_VENDOR_ID" in
            10de) VENDOR_TMP="NVIDIA" ;;
            1002) VENDOR_TMP="AMD" ;;
            8086) VENDOR_TMP="INTEL" ;;
            *)    VENDOR_TMP="UNKNOWN" ;;
        esac

        # Identifica Arquitetura e Rank
        if [ "$VENDOR_TMP" = "NVIDIA" ]; then
            ARCH_TMP=$(get_architecture "$CURRENT_DEVICE_ID")
            RANK_TMP=$(get_rank "$ARCH_TMP")
        else
            ARCH_TMP="n/a"
            RANK_TMP=1 # Rank básico para GPUs não-NVIDIA
        fi

        # Se esta GPU for mais moderna que a anterior, ela assume o posto
        if [ "$RANK_TMP" -gt "$BEST_RANK" ]; then
            BEST_RANK=$RANK_TMP
            FINAL_VENDOR=$VENDOR_TMP
            FINAL_PCI_ID=$CURRENT_PCI_ID
            FINAL_ARCH=$ARCH_TMP
        fi
    done <<< "$GPUS_FOUND"

    # Define o driver baseado na melhor GPU NVIDIA encontrada
    if [ "$FINAL_VENDOR" = "NVIDIA" ]; then
        case "$FINAL_ARCH" in
            blackwell|ada|ampere) DRIVER="open" ;;
            turing|volta|pascal)  DRIVER="legacy" ;;
            *)                    DRIVER="open" ;;
        esac
    else
        DRIVER="none"
    fi

    # Saída Final
    echo "VENDOR=$FINAL_VENDOR"
    echo "PCI_ID=$FINAL_PCI_ID"
    echo "ARCH=$FINAL_ARCH"
    echo "DRIVER=$DRIVER"
}

detect_best_gpu
