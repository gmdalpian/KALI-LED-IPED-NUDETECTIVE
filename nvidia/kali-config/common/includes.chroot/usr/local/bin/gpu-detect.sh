#!/bin/bash

# --- Função de Peso (Ranking) para Arquiteturas ---
get_rank() {
    case "$1" in
        blackwell)  echo 7 ;;
        ada)        echo 6 ;;
        ampere)     echo 5 ;;
        turing)     echo 4 ;;
        volta)      echo 3 ;;
        pascal)     echo 2 ;;
        discrete)   echo 1 ;; # GPUs AMD dedicadas suportadas (RDNA2/3, CDNA)
        integrated) echo 0 ;; # APUs e integradas (Ryzen, Intel, etc)
        *)          echo -1 ;;
    esac
}

# --- Função de Identificação NVIDIA via Device ID ---
get_nvidia_architecture() {
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
        echo "pascal"
    else
        echo "unknown"
    fi
}

# --- Função de Identificação AMD via Device ID ---
get_amd_architecture() {
    PREFIX_HEX=$(echo "$1" | cut -c1-2)

    case "$PREFIX_HEX" in
        73|74)
            # RDNA2 (RX 6000), RDNA3 (RX 7000), CDNA (Instinct MI100/MI200)
            echo "discrete"
            ;;
        66)
            # Vega 20 Dedicada (Radeon VII, MI50)
            echo "discrete"
            ;;
        15|16)
            # APUs (Vídeo Integrado Ryzen: Lucienne, Renoir, Cezanne, Phoenix, etc.)
            # O seu Lucienne 164c cai exatamente aqui.
            echo "integrated"
            ;;
        67|68|69)
            # Polaris (RX 400/500 Series). Sem suporte moderno oficial ao ROCm.
            # Tratamos como integrated/unknown para evitar crash de VRAM.
            echo "unknown"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

detect_best_gpu() {
    # Busca apenas dispositivos da classe de exibição (VGA/3D)
    GPUS_FOUND=$(lspci -nn -d ::0300 && lspci -nn -d ::0302 && lspci -nn -d ::0380)

    if [ -z "$GPUS_FOUND" ]; then
        echo "VENDOR=NONE"
        echo "DRIVER=none"
        return
    fi

    BEST_RANK=-2
    
    while read -r line; do
        CURRENT_PCI_ID=$(echo "$line" | grep -oP '\[\K[0-9a-f]{4}:[0-9a-f]{4}(?=\])')
        CURRENT_VENDOR_ID=$(echo "$CURRENT_PCI_ID" | cut -d: -f1)
        CURRENT_DEVICE_ID=$(echo "$CURRENT_PCI_ID" | cut -d: -f2)

        # Identifica Vendor
        case "$CURRENT_VENDOR_ID" in
            10de) VENDOR_TMP="NVIDIA" ;;
            1002) VENDOR_TMP="AMD"    ;;
            8086) VENDOR_TMP="INTEL"  ;;
            *)    VENDOR_TMP="UNKNOWN" ;;
        esac

        # Identifica Arquitetura baseado no Vendor e Device ID
        if [ "$VENDOR_TMP" = "NVIDIA" ]; then
            ARCH_TMP=$(get_nvidia_architecture "$CURRENT_DEVICE_ID")
            RANK_TMP=$(get_rank "$ARCH_TMP")
        
        elif [ "$VENDOR_TMP" = "AMD" ]; then
            ARCH_TMP=$(get_amd_architecture "$CURRENT_DEVICE_ID")
            RANK_TMP=$(get_rank "$ARCH_TMP")
        
        else
            ARCH_TMP="integrated"
            RANK_TMP=0
        fi

        # Atualiza a melhor GPU encontrada
        if [ "$RANK_TMP" -gt "$BEST_RANK" ]; then
            BEST_RANK=$RANK_TMP
            FINAL_VENDOR=$VENDOR_TMP
            FINAL_PCI_ID=$CURRENT_PCI_ID
            FINAL_ARCH=$ARCH_TMP
        fi
    done <<< "$GPUS_FOUND"

    # Define o Driver/Ambiente a ser usado
    if [ "$FINAL_VENDOR" = "NVIDIA" ]; then
        case "$FINAL_ARCH" in
            blackwell|ada|ampere) DRIVER="open"   ;;
            turing|volta|pascal)  DRIVER="legacy" ;;
            *)                    DRIVER="open"   ;;
        esac
    elif [ "$FINAL_VENDOR" = "AMD" ] && [ "$FINAL_ARCH" = "discrete" ]; then
        # Somente prefixos 73, 74 e 66 cairão aqui (GPUs dedicadas com suporte)
        DRIVER="open"
    else
        # Prefixos 15 e 16 (seu notebook) ou Intel cairão aqui
        DRIVER="none"
    fi

    # Saída
    echo "VENDOR=$FINAL_VENDOR"
    echo "PCI_ID=$FINAL_PCI_ID"
    echo "ARCH=$FINAL_ARCH"
    echo "DRIVER=$DRIVER"
}

detect_best_gpu