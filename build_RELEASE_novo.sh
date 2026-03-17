#!/bin/bash

# --- Configurações de Caminhos ---
BASE_DIR="/home/kali"
EXTERNAL_DISK="/run/media/kali/DISCO_EXTERNO"
RELEASE=$1
ACTION=$2
OPTION=$3
NVIDIA_SOURCE="$EXTERNAL_DISK/nvidia"

# --- Função de Verificação de Integridade (NVIDIA) ---
test_integrity() {
    echo '--- [AÇÃO: CHECK] Validando Módulo NVIDIA no chroot ---'
    # Verifica se o DKMS instalou o módulo (Série 580 p/ RTX 5070 e P620)
    DKMS_STATUS=$(sudo chroot ${BASE_DIR}/kali-live/chroot dkms status)
    
    if [[ $DKMS_STATUS == *"nvidia"* && $DKMS_STATUS == *"installed"* ]]; then
        echo "SUCESSO: Driver NVIDIA compilado com sucesso."
    else
        echo "ERRO CRÍTICO: Falha na compilação do driver NVIDIA via DKMS."
        echo "Status: $DKMS_STATUS"
        exit 1
    fi
}

# --- Função de Cópia e Preparação ---
do_copy() {
    echo '--- [AÇÃO: COPY] Preparando estrutura base ---'
    
    # 1. Limpeza e Clonagem do Repositório do Kali
    sudo rm -rf ${BASE_DIR}/kali-live
    git clone https://gitlab.com/kalilinux/build-scripts/kali-live.git ${BASE_DIR}/kali-live
    
    # 2. Extração das configurações principais (do seu zip)
    unzip -o ${EXTERNAL_DISK}/kali-config.zip -d ${BASE_DIR}/

    # --- BLOCO NVIDIA: Integração da estrutura de pastas ---
    if [[ "$ACTION" == "nvidia" || "$OPTION" == "nvidia" || "$ACTION" == "all" && "$OPTION" == "nvidia" ]]; then
        echo "--- [AÇÃO: NVIDIA] Mesclando estrutura de pastas de $NVIDIA_SOURCE ---"
        
        if [ -d "$NVIDIA_SOURCE/kali-config" ]; then
            # Copia recursivamente preservando a estrutura (apt/, archives/, etc)
            cp -Rf "$NVIDIA_SOURCE/kali-config/"* "${BASE_DIR}/kali-config/"
            echo "Estrutura NVIDIA integrada com sucesso."
        else
            echo "ERRO: Estrutura $NVIDIA_SOURCE/kali-config não encontrada!"
            exit 1
        fi
    fi

    # 3. Processamento das bibliotecas Python (scripts de IA/Forense)
    mkdir -p ${BASE_DIR}/kali-config/common/includes.chroot/usr/local/lib
    for f in ${EXTERNAL_DISK}/python/*.tar.gz; do
        [ -e "$f" ] && tar -vzxf "$f" -C ${BASE_DIR}/kali-config/common/includes.chroot/usr/local/lib
    done

    # 4. Sincronização Final para a pasta de build
    chmod -R +x ${BASE_DIR}/kali-config
    cp -Rf ${BASE_DIR}/kali-config/* ${BASE_DIR}/kali-live/kali-config/
}

# --- Função de Compilação da ISO ---
do_build() {
    echo '--- [AÇÃO: BUILD] Iniciando compilação da ISO ---'
    cd ${BASE_DIR}/kali-live

    # bootstrap-packages essencial para o APT lidar com HTTPS no início do build
    time ./build.sh \
      --verbose \
      --distribution kali-last-snapshot \
      --version $RELEASE \
      --bootstrap-packages "ca-certificates gnupg"

    # Validação automática se a opção NVIDIA foi solicitada
    if [[ "$ACTION" == "nvidia" || "$OPTION" == "nvidia" || "$ACTION" == "all" ]]; then
        test_integrity
    fi

    # Gestão do arquivo final
    ISO_NAME="kali-linux-$RELEASE-live-amd64.iso"
    ISO_PATH="${BASE_DIR}/kali-live/images/${ISO_NAME}"

    if [ -f "$ISO_PATH" ]; then
        md5sum "$ISO_PATH" > "${ISO_PATH}.md5"
        rm -rf ${EXTERNAL_DISK}/images/*
        FINAL_NAME="KALI-IA-FORENSIC-$(date -I)"
        cp "$ISO_PATH" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso"
        cp "${ISO_PATH}.md5" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso.md5"
        echo "ISO gerada e copiada para o disco externo: ${FINAL_NAME}.iso"
    fi
}

# --- Lógica Principal ---
if [ -z "$RELEASE" ] || [ -z "$ACTION" ]; then
    echo "Uso: $0 <VERSAO> <all|copy|build|nvidia> [nvidia]"
    exit 1
fi

case $ACTION in
    all) do_copy; do_build ;;
    copy) do_copy ;;
    build) do_build ;;
    nvidia) do_copy; do_build ;;
    *) echo "Erro: Ação '$ACTION' inválida."; exit 1 ;;
esac
