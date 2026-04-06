#!/bin/bash

# --- Configurações de Caminhos ---
BASE_DIR="/home/kali"
EXTERNAL_DISK="/run/media/kali/DISCO_EXTERNO"
RELEASE=$1
ACTION=$2
OPTION=$3
NVIDIA_SOURCE="$EXTERNAL_DISK/nvidia"

# --- Função de Verificação de Erro ---
check_status() {
    if [ $? -ne 0 ]; then
        echo "ERRO CRÍTICO: $1 falhou. Abortando."
        exit 1
    fi
}

# --- Função de Cópia e Preparação ---
do_copy() {
    echo '--- [AÇÃO: COPY] Preparando estrutura base ---'
    
    # 1. Limpeza e Clonagem do Repositório do Kali
    sudo rm -rf ${BASE_DIR}/kali-live
    sudo rm -rf ${BASE_DIR}/kali-config
    
    git clone https://gitlab.com/kalilinux/build-scripts/kali-live.git ${BASE_DIR}/kali-live
    check_status "Clonagem do repositório kali-live"
    
    # 2. Extração das configurações principais
    7z x ${EXTERNAL_DISK}/kali-config.zip -o${BASE_DIR}/
    check_status "Extração do arquivo kali-config.zip"

    # --- BLOCO NVIDIA: Integração da estrutura de pastas ---
    if [[ "$ACTION" == "nvidia" || "$OPTION" == "nvidia" || "$ACTION" == "all" && "$OPTION" == "nvidia" ]]; then
        echo "--- [AÇÃO: NVIDIA] Mesclando estrutura de pastas de $NVIDIA_SOURCE ---"
        
        if [ -d "$NVIDIA_SOURCE/kali-config" ]; then
            cp -Rf "$NVIDIA_SOURCE/kali-config/"* "${BASE_DIR}/kali-config/"
            check_status "Cópia da estrutura NVIDIA"
            echo "Estrutura NVIDIA integrada com sucesso."
        else
            echo "ERRO: Estrutura $NVIDIA_SOURCE/kali-config não encontrada!"
            exit 1
        fi
    fi

    # 3. Processamento das bibliotecas Python (scripts de IA/Forense)
    mkdir -p ${BASE_DIR}/kali-config/common/includes.chroot/usr/local/lib
    
    for f in ${EXTERNAL_DISK}/python/PYTHON*; do
        if [ -e "$f" ]; then
            tar -vzxf "$f" -C ${BASE_DIR}/kali-config/common/includes.chroot/usr/local/lib
            check_status "Extração da biblioteca Python: $f"
        fi
    done	

    if [[ "$ACTION" == "nvidia" || "$OPTION" == "nvidia" || "$ACTION" == "all" && "$OPTION" == "nvidia" ]]; then
        mkdir -p ${BASE_DIR}/kali-config/common/includes.chroot/opt
        for f in ${EXTERNAL_DISK}/python/NVIDIA*; do
            if [ -e "$f" ]; then
                tar -vzxf "$f" -C ${BASE_DIR}/kali-config/common/includes.chroot/opt
                check_status "Extração dos pacotes NVIDIA: $f"
            fi
        done
    fi    

    # 4. Sincronização Final para a pasta de build
    chmod -R +x ${BASE_DIR}/kali-config
    cp -Rf ${BASE_DIR}/kali-config/* ${BASE_DIR}/kali-live/kali-config/
    check_status "Sincronização final para a pasta de build"

    # --- LIMPEZA DE ESPAÇO ---
    echo "Limpando diretório temporário para liberar espaço..."
    sudo rm -rf ${BASE_DIR}/kali-config/
    echo "Diretório ${BASE_DIR}/kali-config/ removido."
}

# --- Função de Compilação da ISO ---
do_build() {
    echo '--- [AÇÃO: BUILD] Iniciando compilação da ISO ---'
    cd ${BASE_DIR}/kali-live || exit 1

    # bootstrap-packages essencial para o APT lidar com HTTPS no início do build
    time ./build.sh \
      --verbose \
      --distribution kali-last-snapshot \
      --version $RELEASE
    
    check_status "Compilação da ISO (build.sh)"

    # Gestão do arquivo final
    ISO_NAME="kali-linux-$RELEASE-live-amd64.iso"
    ISO_PATH="${BASE_DIR}/kali-live/images/${ISO_NAME}"

    if [ -f "$ISO_PATH" ]; then
        md5sum "$ISO_PATH" > "${ISO_PATH}.md5"
        FINAL_NAME="KALI-LED-IPED-NUDETECTIVE-$(date -I)-CSAM-TRIAGE"
        if [[ "$ACTION" == "nvidia" || "$OPTION" == "nvidia" ]]; then
            FINAL_NAME+="_NVIDIA"
        fi
        cp "$ISO_PATH" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso"
        check_status "Cópia da ISO final para o disco externo"
        
        cp "${ISO_PATH}.md5" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso.md5"
        echo "ISO gerada e copiada para o disco externo: ${FINAL_NAME}.iso"
    else
        echo "ERRO: O arquivo ISO não foi encontrado em $ISO_PATH"
        exit 1
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
