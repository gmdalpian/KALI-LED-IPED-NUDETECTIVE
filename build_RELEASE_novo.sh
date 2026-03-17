#!/bin/bash

# --- Configurações de Caminhos ---
BASE_DIR="/home/kali"
EXTERNAL_DISK="/run/media/kali/DISCO_EXTERNO"
RELEASE=$1
ACTION=$2
OPTION=$3

# --- Função de Cópia e Preparação ---
do_copy() {
    echo '--- [AÇÃO: COPY] Preparando arquivos ---'
    
    echo '1. Resetando diretório kali-live...'
    sudo rm -rf ${BASE_DIR}/kali-live
    git clone https://gitlab.com/kalilinux/build-scripts/kali-live.git ${BASE_DIR}/kali-live

    echo '2. Extraindo configurações customizadas...'
    unzip -o ${EXTERNAL_DISK}/kali-config.zip -d ${BASE_DIR}/

    echo '3. Instalando bibliotecas Python...'
    mkdir -p ${BASE_DIR}/kali-config/common/includes.chroot/usr/local/lib
    for f in ${EXTERNAL_DISK}/python/*.tgz; do
        [ -e "$f" ] && tar -vzxf "$f" -C ${BASE_DIR}/kali-config/common/includes.chroot/usr/local/lib
    done

    # Lógica para NVIDIA (verifica se 'nvidia' foi passado como 2º ou 3º parâmetro)
    if [[ "$ACTION" == "nvidia" || "$OPTION" == "nvidia" || "$ACTION" == "all" && "$OPTION" == "nvidia" ]]; then
        echo '3.1 [OPCIONAL] Integrando conteúdo da pasta /nvidia...'
        if [ -d "${EXTERNAL_DISK}/nvidia" ]; then
            cp -Rf ${EXTERNAL_DISK}/nvidia/* ${BASE_DIR}/
        else
            echo "AVISO: Pasta /nvidia não encontrada. Pulando..."
        fi
    fi

    echo '4. Sincronizando com a estrutura do live-build...'
    chmod -R +x ${BASE_DIR}/kali-config
    cp -Rf ${BASE_DIR}/kali-config/* ${BASE_DIR}/kali-live/kali-config/
}

# --- Função de Compilação da ISO ---
do_build() {
    echo '--- [AÇÃO: BUILD] Gerando ISO ---'
    cd ${BASE_DIR}/kali-live

    time ./build.sh \
      --verbose \
      --distribution kali-last-snapshot \
      --version $RELEASE 

    ISO_NAME="kali-linux-$RELEASE-live-amd64.iso"
    ISO_PATH="${BASE_DIR}/kali-live/images/${ISO_NAME}"

    if [ -f "$ISO_PATH" ]; then
        echo '2. Gerando MD5 e movendo para o disco externo...'
        md5sum "$ISO_PATH" > "${ISO_PATH}.md5"
        rm -rf ${EXTERNAL_DISK}/images/*
        
        FINAL_NAME="KALI-LED-IPED-NUDETECTIVE-$(date -I)"
        cp "$ISO_PATH" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso"
        cp "${ISO_PATH}.md5" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso.md5"
        echo "Sucesso! ISO em: ${EXTERNAL_DISK}/images/${FINAL_NAME}.iso"
    else
        echo "ERRO: O arquivo ISO não foi gerado. Verifique os logs do build."
        exit 1
    fi
}

# --- Lógica de Execução Principal ---

# Se não houver argumentos ou faltar a versão, mostra o Help
if [ -z "$RELEASE" ] || [ -z "$ACTION" ]; then
    echo "Modo de uso: $0 <VERSAO> <all|copy|build|nvidia> [nvidia]"
    echo "--------------------------------------------------------"
    echo "  all      -> Executa copy + build"
    echo "  copy     -> Apenas prepara os arquivos"
    echo "  build    -> Apenas gera o ISO (assume que copy já foi feito)"
    echo "  nvidia   -> Executa tudo incluindo drivers NVIDIA"
    echo ""
    echo "Exemplos:"
    echo "  $0 2026.1 all          (Processo completo padrão)"
    echo "  $0 2026.1 all nvidia   (Processo completo + NVIDIA)"
    echo "  $0 2026.1 copy         (Só prepara pastas)"
    exit 1
fi

case $ACTION in
    all)
        do_copy
        do_build
        ;;
    copy)
        do_copy
        ;;
    build)
        do_build
        ;;
    nvidia)
        # Mantido para compatibilidade caso você digite apenas 'nvidia'
        do_copy
        do_build
        ;;
    *)
        echo "Erro: Ação '$ACTION' inválida."
        exit 1
        ;;
esac
