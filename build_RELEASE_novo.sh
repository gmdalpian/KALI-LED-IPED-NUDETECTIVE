#!/bin/bash

# --- Configurações de Caminhos ---
BASE_DIR="/home/kali"
EXTERNAL_DISK="/run/media/kali/DISCO_EXTERNO"
RELEASE=$1
ACTION=$2
NVIDIA_SOURCE="$EXTERNAL_DISK/nvidia"

# --- Avaliação de Flags Auxiliares ---
NVIDIA_FLAG=false
GLOBAL_FLAG=false

# Verifica todos os argumentos passados para ativar as flags, independente da ordem
for arg in "$@"; do
    if [[ "$arg" == "nvidia" ]]; then NVIDIA_FLAG=true; fi
    if [[ "$arg" == "global" ]]; then GLOBAL_FLAG=true; fi
done

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
    check_status "Remoção do diretório antigo kali-live"
    
    sudo rm -rf ${BASE_DIR}/kali-config
    check_status "Remoção do diretório temporário antigo kali-config"
    
    git clone https://gitlab.com/kalilinux/build-scripts/kali-live.git ${BASE_DIR}/kali-live
    check_status "Clonagem do repositório kali-live"
    
    # 2. Cópia das configurações principais direto para a pasta final
    mkdir -p ${BASE_DIR}/kali-live/kali-config
    check_status "Criação do diretório de destino kali-config"

    cp -Rf ${EXTERNAL_DISK}/kali-config/* ${BASE_DIR}/kali-live/kali-config/
    check_status "Cópia direta do diretório kali-config"

    # --- BLOCO NVIDIA: Integração da estrutura de pastas ---
    if [ "$NVIDIA_FLAG" = true ]; then
        echo "--- [AÇÃO: NVIDIA] Mesclando estrutura de pastas de $NVIDIA_SOURCE ---"
        
        if [ -d "$NVIDIA_SOURCE/kali-config" ]; then
            cp -Rf "$NVIDIA_SOURCE/kali-config/"* "${BASE_DIR}/kali-live/kali-config/"
            check_status "Cópia da estrutura NVIDIA"
            echo "Estrutura NVIDIA integrada com sucesso."
        else
            echo "ERRO: Estrutura $NVIDIA_SOURCE/kali-config não encontrada!"
            exit 1
        fi
    fi

    # 3. Processamento das bibliotecas Python (scripts de IA/Forense)
    mkdir -p ${BASE_DIR}/kali-live/kali-config/common/includes.chroot/usr/local/lib
    check_status "Criação do diretório lib para Python"
    
    for f in ${EXTERNAL_DISK}/python/PYTHON*; do
        if [ -e "$f" ]; then
            tar -vzxf "$f" -C ${BASE_DIR}/kali-live/kali-config/common/includes.chroot/usr/local/lib
            check_status "Extração da biblioteca Python: $f"
        fi
    done	

    if [ "$NVIDIA_FLAG" = true ]; then
        mkdir -p ${BASE_DIR}/kali-live/kali-config/common/includes.chroot/opt
        check_status "Criação do diretório opt para NVIDIA"
        
        for f in ${EXTERNAL_DISK}/python/NVIDIA*; do
            if [ -e "$f" ]; then
                tar -vzxf "$f" -C ${BASE_DIR}/kali-live/kali-config/common/includes.chroot/opt
                check_status "Extração dos pacotes NVIDIA: $f"
            fi
        done
    fi    

    # --- BLOCO GLOBAL: Customizações pré-build ---
    if [ "$GLOBAL_FLAG" = true ]; then
        echo '--- [AÇÃO: GLOBAL] Customizando versão global ---'
        
        # Remoção de atalhos e binários proprietários
        rm -rf "${BASE_DIR}/kali-live/kali-config/common/includes.chroot/usr/local/bin/LED"
        check_status "Remoção do binário LED"
        
        rm -rf "${BASE_DIR}/kali-live/kali-config/common/includes.chroot/usr/local/bin/NuDetective"
        check_status "Remoção do binário NuDetective"
        
        rm -rf "${BASE_DIR}/kali-live/kali-config/common/includes.chroot/etc/skel/Desktop/LED - Escolher Midia.desktop"
        check_status "Remoção de atalho: LED - Escolher Midia"
        
        rm -rf "${BASE_DIR}/kali-live/kali-config/common/includes.chroot/etc/skel/Desktop/LED - Montar e Vasculhar.desktop"
        check_status "Remoção de atalho: LED - Montar e Vasculhar"
        
        rm -rf "${BASE_DIR}/kali-live/kali-config/common/includes.chroot/etc/skel/Desktop/Nudetective.desktop"
        check_status "Remoção de atalho: Nudetective"
        
        # Cópia do papel de parede
        mkdir -p "${BASE_DIR}/kali-live/kali-config/common/includes.chroot/usr/share/backgrounds/kali/"
        check_status "Criação do diretório para papel de parede"
        
        cp -f "${EXTERNAL_DISK}/kali-config/common/includes.chroot/etc/skel/Pictures/background_global_new_4x3.jpg" \
              "${BASE_DIR}/kali-live/kali-config/common/includes.chroot/usr/share/backgrounds/kali/kali-cubes-16x9.jpg"
        check_status "Cópia do papel de parede global"
    fi

    # --- BLOCO DE TRADUÇÃO: Compilação de .po para .mo ---
    echo '--- [AÇÃO: LOCALE] Compilando arquivos de tradução (.po para .mo) ---'
    LOCALE_SRC="${EXTERNAL_DISK}/locale"
    
    if [ -d "$LOCALE_SRC" ]; then
        # Busca todos os arquivos .po na estrutura
        find "$LOCALE_SRC" -type f -name "*.po" | while read -r po_file; do
            # Identifica se o arquivo está dentro de um diretório LC_MESSAGES
            msg_dir=$(dirname "$po_file")
            if [ "$(basename "$msg_dir")" == "LC_MESSAGES" ]; then
                # Extrai o nome da linguagem (ex: pt_BR) que é o diretório pai do LC_MESSAGES
                lang=$(basename "$(dirname "$msg_dir")")
                
                # Define e cria o diretório de destino na estrutura de chroot do Kali
                dest_dir="${BASE_DIR}/kali-live/kali-config/common/includes.chroot/usr/share/locale/$lang/LC_MESSAGES"
                mkdir -p "$dest_dir"
                check_status "Criação do diretório locale para $lang"
                
                # Nome do arquivo de saída .mo
                filename=$(basename "$po_file" .po)
                
                # Compila o .po para .mo
                msgfmt -o "$dest_dir/$filename.mo" "$po_file"
                check_status "Compilação do locale $lang ($filename.mo)"
            fi
        done
        echo "Traduções compiladas e integradas na chroot com sucesso."
    else
        echo "Aviso: Diretório de origens de tradução ($LOCALE_SRC) não encontrado. Ignorando compilação de idiomas."
    fi

    echo "Arquivos copiados e preparados com sucesso diretamente em kali-live/kali-config."
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
        check_status "Geração do checksum MD5"
        
        # Construção dinâmica do nome da ISO com base nas flags
        FINAL_NAME="KALI-LED-IPED-NUDETECTIVE-$(date -I)-CSAM-TRIAGE"
        
        if [ "$NVIDIA_FLAG" = true ]; then
            FINAL_NAME="${FINAL_NAME}_NVIDIA"
        fi
        
        if [ "$GLOBAL_FLAG" = true ]; then
            FINAL_NAME="${FINAL_NAME}_GLOBAL"
        fi

        cp "$ISO_PATH" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso"
        check_status "Cópia da ISO final para o disco externo"
        
        cp "${ISO_PATH}.md5" "${EXTERNAL_DISK}/images/${FINAL_NAME}.iso.md5"
        check_status "Cópia do checksum para o disco externo"
        
        echo "ISO gerada e copiada para o disco externo: ${FINAL_NAME}.iso"
    else
        echo "ERRO: O arquivo ISO não foi encontrado em $ISO_PATH"
        exit 1
    fi
}

# --- Lógica Principal ---
if [ -z "$RELEASE" ] || [ -z "$ACTION" ]; then
    echo "Uso: $0 <VERSAO> <all|copy|build> [nvidia] [global]"
    exit 1
fi

# Se a ação passada for diretamente uma das flags, forçamos o ciclo completo ('all')
if [[ "$ACTION" == "nvidia" || "$ACTION" == "global" ]]; then
    ACTION="all"
fi

case $ACTION in
    all) do_copy; do_build ;;
    copy) do_copy ;;
    build) do_build ;;
    *) echo "Erro: Ação '$ACTION' inválida. Use all, copy ou build."; exit 1 ;;
esac