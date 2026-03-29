#!/bin/bash
#
# iped_executor.sh
# Script "motor" para execução do IPED.
# (Versão com Arrays Nativos para proteção contra espaços e caminhos complexos)
#

source /home/kali/forensic_utils.sh

# --- Constantes ---
IPED_DIR="/usr/local/bin/iped"
# Base do comando separada em Array mais abaixo
OUTPUT_DIR_DESKTOP="/home/kali/Desktop/IPED-CASO"
OUTPUT_DIR_TRIAGE_BASE="/home/kali/Desktop/triage"
OUTPUT_DIR_TRIAGE_CASE="$OUTPUT_DIR_TRIAGE_BASE/IPED-CASO"
COMMAND_LOG_FILE="/home/kali/Desktop/iped_comando_executado.log"
MEDIA_DIR="/run/media"
GPU_DETECT_SCRIPT="/usr/local/bin/gpu-detect.sh"

# --- Variáveis de Ambientes Python (Venvs) ---
VENV_CUDA="/opt/venv-cuda/bin/activate"
VENV_CUDA_LEGACY="/opt/venv-cuda-legacy/bin/activate"
VENV_ROCM="/opt/venv-rocm/bin/activate"

# --- Variáveis Globais ---
CONTINUE_PROCESSING=false
RECOVERED_CMD=""
KALI_UID=1000
KALI_GID=1000
TARGET_ARRAY=() # Array global para armazenar os alvos com segurança

# --- Funções de Lógica ---

# Função para lidar com BitLocker (Agora usa Arrays)
handle_bitlocker() {
    local disk_device=$1
    local root_system=$2
    local disk_basename=$(basename "$disk_device")

    if [[ "$disk_basename" != *"$root_system"* ]]; then
        echo "Detectado bitlocker em $disk_device"
        sudo mkdir -p "/dislocker/bitlocker_$disk_basename"

        sudo dislocker -V "$disk_device" -- "/dislocker/bitlocker_$disk_basename" -r
        if sudo test -f "/dislocker/bitlocker_$disk_basename/dislocker-file"; then
            echo "Bitlocker (sem senha) montado."
            sudo ln -sf "/dislocker/bitlocker_$disk_basename/dislocker-file" "/dislocker/dislocker-file_$disk_basename.dd"
            TARGET_ARRAY+=("-d" "/dislocker/dislocker-file_$disk_basename.dd")
        else
            while true; do
                BITLOCKER_INFO=('', '')
                while read -r line ; do
                    [[ $line =~ "Description:" ]] && BITLOCKER_INFO[0]=$line
                    [[ $line =~ "VMK protected with recovery passphrase" ]] && BITLOCKER_INFO[1]=${previousline^^}
                    previousline=$line
                done <<< "$(sudo cryptsetup bitlkDump "$disk_device")"

                bitlocker_pass=$(zenity --entry --title="Detectado BitLocker!" \
                    --text="Partição criptografada em $disk_device.\nDigite a senha ou chave de recuperação:\n\n${BITLOCKER_INFO[0]}\n${BITLOCKER_INFO[1]}" \
                    --entry-text "ChaveDeRecuperacao" --width=500)

                if [ $? = 0 ]; then
                    sudo dislocker -V "$disk_device" -p"$bitlocker_pass" -- "/dislocker/bitlocker_$disk_basename" -r
                    if sudo test -f "/dislocker/bitlocker_$disk_basename/dislocker-file"; then
                        echo "Bitlocker decifrado com chave de recuperação."
                        sudo ln -sf "/dislocker/bitlocker_$disk_basename/dislocker-file" "/dislocker/dislocker-file_$disk_basename.dd"
                        TARGET_ARRAY+=("-d" "/dislocker/dislocker-file_$disk_basename.dd")
                        break
                    else
                        sudo dislocker -V "$disk_device" --user-password="$bitlocker_pass" -- "/dislocker/bitlocker_$disk_basename" -r
                        if sudo test -f "/dislocker/bitlocker_$disk_basename/dislocker-file"; then
                            echo "Bitlocker decifrado com senha de usuário."
                            sudo ln -sf "/dislocker/bitlocker_$disk_basename/dislocker-file" "/dislocker/dislocker-file_$disk_basename.dd"
                            TARGET_ARRAY+=("-d" "/dislocker/dislocker-file_$disk_basename.dd")
                            break
                        else
                            zenity --error --title="Erro de Chave BitLocker!" --text="A chave ou senha fornecida não decifrou a unidade." --width=300 --timeout=10
                        fi
                    fi
                else
                    echo "Usuário cancelou a inserção de senha do Bitlocker."
                    break
                fi
            done
        fi
    fi
}

# Lógica para encontrar e montar partição de triagem
setup_output_dir() {
    echo "Configurando diretório de saída..."
    
    local triage_part_device=$(get_triage_device)
    local TRIAGE_PARTITION_FOUND=false
    [ -n "$triage_part_device" ] && TRIAGE_PARTITION_FOUND=true

    if $TRIAGE_PARTITION_FOUND; then
        echo "Dispositivo de destino identificado: $triage_part_device"
        OUTPUT_DIR=$OUTPUT_DIR_TRIAGE_CASE
        DESKTOP_FILE="IPED-Caso-triage.desktop"
        
        if [ ! -d "$OUTPUT_DIR_TRIAGE_BASE" ]; then
             mkdir -p "$OUTPUT_DIR_TRIAGE_BASE"
        fi

        if findmnt --mountpoint $OUTPUT_DIR_TRIAGE_BASE &> /dev/null; then
             echo "Partição Triage já está montada."
             if [ "$(stat -c '%u' "$OUTPUT_DIR_TRIAGE_BASE")" != "$KALI_UID" ]; then
                  sudo umount "$OUTPUT_DIR_TRIAGE_BASE" &> /dev/null
                  if ! sudo mount -o rw,uid=$KALI_UID,gid=$KALI_GID $triage_part_device $OUTPUT_DIR_TRIAGE_BASE; then
                       TRIAGE_PARTITION_FOUND=false
                       OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
                       DESKTOP_FILE="IPED-Caso.desktop"
                  fi
             fi
        else
            if ! sudo mount -o rw,uid=$KALI_UID,gid=$KALI_GID $triage_part_device $OUTPUT_DIR_TRIAGE_BASE; then
                TRIAGE_PARTITION_FOUND=false
                OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
                DESKTOP_FILE="IPED-Caso.desktop"
            fi
        fi

        if $TRIAGE_PARTITION_FOUND; then
            LOG_FILE_PATH="$OUTPUT_DIR_TRIAGE_BASE/IPED-Processamento-$(date +%y%m%d%H%M).log"
            if test -f "$OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"; then
                KEYWORD_FILE_PATH="$OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"
            else
                KEYWORD_FILE_PATH="$IPED_DIR/palavras-chave.txt"
            fi
            
            sudo cp "$IPED_DIR/LocalConfig-triage.txt" "$IPED_DIR/LocalConfig.txt"

            # Lógica de SWAP
            if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
                if [ "$(cat /proc/swaps | wc -l)" -le 1 ]; then
                    local swap_file_path="$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                    if test -f "$swap_file_path"; then
                         sudo swapon "$swap_file_path"
                         if [ $? -ne 0 ]; then
                             sudo swapoff "$swap_file_path" &> /dev/null
                             rm -f "$swap_file_path"
                         else
                              local create_swap=false
                         fi
                    fi

                    if [ ! -f "$swap_file_path" ] || [ "$create_swap" != "false" ]; then
                         available_kb=$(df -k "$OUTPUT_DIR_TRIAGE_BASE" | tail -n 1 | awk '{print $4}')
                         available_kb=${available_kb:-0}

                         if (( available_kb > 102400 )); then
                              target_kb=$((available_kb / 10))
                              max_kb=$((10 * 1024 * 1024))
                              (( target_kb > max_kb )) && swap_size_kb=$max_kb || swap_size_kb=$target_kb
                              swap_size_mb=$((swap_size_kb / 1024))

                              if truncate -s "${swap_size_mb}M" "$swap_file_path"; then
                                   sudo mkswap "$swap_file_path"
                                   sudo swapon "$swap_file_path" || rm -f "$swap_file_path"
                              fi
                         fi
                    fi
                fi
            fi 
        fi 

    else 
        echo "Nenhuma partição IPED-TRIAGE encontrada. Usando Desktop."
        OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
        DESKTOP_FILE="IPED-Caso.desktop"
        LOG_FILE_PATH=""
        KEYWORD_FILE_PATH="$IPED_DIR/palavras-chave.txt"
    fi

    if [ -d "$OUTPUT_DIR" ]; then
        if zenity --question --title="Caso Existente" \
            --text="Um caso já existe em:\n<b>$OUTPUT_DIR</b>\n\nO que deseja fazer?" \
            --ok-label="Processar Novamente (Apagar)" \
            --cancel-label="Continuar Anterior" \
            --width=450;
        then
            sudo rm -rf "$OUTPUT_DIR" || exit 6
            sudo mkdir -p "$OUTPUT_DIR"
            sudo chown $KALI_UID:$KALI_GID "$OUTPUT_DIR"
            CONTINUE_PROCESSING=false
        else
            CONTINUE_PROCESSING=true
            if [ -f "$COMMAND_LOG_FILE" ]; then
                 local escaped_output_dir=$(sed 's#[&/\]#\\&#g' <<<"$OUTPUT_DIR")
                 local original_cmd=$(grep "$escaped_output_dir" "$COMMAND_LOG_FILE" | tail -n 1 | sed 's/^\[.*\] Executando: //')

                 if [ -z "$original_cmd" ]; then exit 7; fi
                 
                 local original_profile=$(echo "$original_cmd" | grep -o '\-profile [^ ]*' | awk '{print $2}' | tr -d "'\"")
                 PROFILE=$original_profile

                 if echo "$original_cmd" | grep -q -- "-jar iped.jar"; then
                     if ! echo "$original_cmd" | grep -q -- '--continue'; then
                          RECOVERED_CMD=$(echo "$original_cmd" | sed 's/-jar iped\.jar/-jar iped.jar --continue/')
                     else
                          RECOVERED_CMD="$original_cmd"
                     fi
                 else
                     exit 9
                 fi
            else
                 exit 7
            fi
        fi
    else
        sudo mkdir -p "$OUTPUT_DIR"
        sudo chown $KALI_UID:$KALI_GID "$OUTPUT_DIR"
        CONTINUE_PROCESSING=false
    fi
}

# --- ATUALIZAÇÃO: Monta o array de alvos usando forensic_utils.sh ---
build_targets() {
    TARGET_ARRAY=()
    local root_system=$(get_boot_disk_name)

    case $TARGET_MODE in
        "all_disks")
            echo "Construindo alvos: Discos"

            # 1. Discos Físicos
            while read -r line ; do
                local disk=$(echo "$line" | awk '{print $1}')
                if [[ "$disk" != "$root_system" ]]; then
                    TARGET_ARRAY+=("-d" "/dev/$disk")
                fi
            done <<< "$(lsblk -lno NAME,TYPE | grep disk)"

            # 2. LDM (RAID Windows)
            sudo ldmtool create all &> /dev/null
            while read -r line ; do
                local disk=$(echo "$line" | awk '{print $1}')
                TARGET_ARRAY+=("-d" "/dev/mapper/$disk")
            done <<< "$(lsblk -lno NAME,TYPE | grep '\dm\b')"

            # 3. VSS
            if [ -d "/vss" ]; then
                sudo mkdir -p /vss_iped
                while read -r line ; do
                    for vss in $(sudo ls /vss/$line 2>/dev/null); do
                        sudo ln -sf "/vss/$line/$vss" "/vss_iped/$line-$vss.dd"
                        TARGET_ARRAY+=("-d" "/vss_iped/$line-$vss.dd")
                    done
                done <<< "$(sudo ls /vss/ 2>/dev/null)"
            fi

            # 4. BitLocker
            sudo mkdir -p /dislocker
            while read -r line ; do
                if [ ! -z "$line" ]; then
                    handle_bitlocker "$line" "$root_system"
                fi
            done <<< "$(sudo dislocker-find)"
            ;;

        "mounted_files")
            echo "Construindo alvos: Arquivos Montados"
            if [ -f "/home/kali/mount_disks.sh" ]; then
                /home/kali/mount_disks.sh
            fi
            TARGET_ARRAY+=("-d" "$MEDIA_DIR")
            ;;

        "manual_dir")
            echo "Construindo alvos: Seleção Manual"
            if [ -z "$MANUAL_PATH" ]; then exit 5; fi
            # O Array aceita espaços normalmente
            TARGET_ARRAY+=("-d" "$MANUAL_PATH")
            ;;
    esac

    if [ ${#TARGET_ARRAY[@]} -eq 0 ]; then
        zenity --error --text="Nenhum alvo de processamento foi determinado."
        exit 3
    fi
}

run_post_processing() {
    echo "Iniciando pós-processamento..."
    cp "$IPED_DIR/Ferramenta_de_Pesquisa.sh" "$OUTPUT_DIR/"
    cp "$IPED_DIR/$DESKTOP_FILE" "/home/kali/Desktop/IPED-Caso.desktop"
    sudo chown kali:kali "/home/kali/Desktop/IPED-Caso.desktop" || true
    
    cd "$OUTPUT_DIR"
    if [ -f "./Ferramenta_de_Pesquisa.sh" ]; then
        ./Ferramenta_de_Pesquisa.sh
    fi
}

# --- Função Principal (Main) ---

if [ $# -eq 0 ]; then exit 1; fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile) SELECTED_PROFILE="$2"; shift ;;
        --target) TARGET_MODE="$2"; shift ;;
        --path) MANUAL_PATH="$2"; shift ;;
        *) echo "Parâmetro desconhecido: $1"; exit 1 ;;
    esac
    shift
done
PROFILE=$SELECTED_PROFILE

cd "$IPED_DIR" || exit 1
sudo mplayer &> /dev/null

setup_output_dir

if ! $CONTINUE_PROCESSING; then
     build_targets 
fi

# =========================================================
# DETECÇÃO DE GPU
# =========================================================
PYTHON_TARGET=""
if [ -f "$GPU_DETECT_SCRIPT" ]; then
    eval $($GPU_DETECT_SCRIPT) 
    
    CANDIDATO=""
    if [ "$VENDOR" = "NVIDIA" ]; then
        [ "$DRIVER" = "open" ] && CANDIDATO="$VENV_CUDA"
        [ "$DRIVER" = "legacy" ] && CANDIDATO="$VENV_CUDA_LEGACY"
    elif [ "$VENDOR" = "AMD" ]; then
        CANDIDATO="$VENV_ROCM"
    fi

    if [ -n "$CANDIDATO" ] && [ -f "$CANDIDATO" ]; then
        PYTHON_TARGET="$CANDIDATO"
    fi
fi
# =========================================================
    
# =========================================================
# 4. Construção Segura do Comando (ARRAYS + POSICIONAL)
# =========================================================
if $CONTINUE_PROCESSING; then
    FINAL_CMD=$RECOVERED_CMD
    echo "========================================================"
    echo "COMANDO PARA CONTINUAR (Perfil Original '$PROFILE'):"
    echo "$FINAL_CMD"
    echo "========================================================"
    
    # 5. Execução Continuação
    eval "$FINAL_CMD"
    
    if [ $? -ne 0 ]; then
        zenity --error --text="Ocorreu um erro durante a continuação do processamento do IPED.\nVerifique o log neste terminal ou em $LOG_FILE_PATH" --width=500
        exit 4
    fi
else
    # Cria a base do comando como um Array
    IPED_CMD=("java" "--module-path" "/usr/share/openjfx/lib/" "--add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base" "-jar" "iped.jar" "-o" "$OUTPUT_DIR" "-profile" "$PROFILE")
    
    if [ -n "$LOG_FILE_PATH" ]; then
        IPED_CMD+=("-log" "$LOG_FILE_PATH")
    fi
    if [ -n "$KEYWORD_FILE_PATH" ]; then
        IPED_CMD+=("-l" "$KEYWORD_FILE_PATH")
    fi
    
    # Anexa o array de alvos (nativamente imune a espaços)
    IPED_CMD+=("${TARGET_ARRAY[@]}")

    # Cria uma string legível para o LOG e para a futura continuação
    SAFE_ARGS=$(printf "%q " "${IPED_CMD[@]}")
    
    if [ -n "$PYTHON_TARGET" ]; then
        # O TRUQUE: Passamos a lógica no bash -c, mas os dados vêm FORA das aspas.
        # O '--' vira $0, o PYTHON_TARGET vira $1 e o resto vira $@
        LOG_CMD="sudo bash -c 'source \"\$1\"; shift; exec \"\$@\"' -- $(printf "%q" "$PYTHON_TARGET") $SAFE_ARGS"
    else
        LOG_CMD="sudo $SAFE_ARGS"
    fi

    echo "========================================================"
    echo "COMANDO FINAL A SER EXECUTADO:"
    echo "$LOG_CMD"
    echo "========================================================"

    # LOG DO COMANDO
    echo "Registrando comando em $COMMAND_LOG_FILE..."
    mkdir -p "$(dirname "$COMMAND_LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executando: $LOG_CMD" >> "$COMMAND_LOG_FILE"
    chown kali:kali "$COMMAND_LOG_FILE" || echo "Aviso: Falha ao mudar proprietário do arquivo de log."

    echo "Iniciando IPED... Isso pode levar muito tempo."

    # =========================================================
    # 5. Execução Principal (A MÁGICA ACONTECE AQUI)
    # =========================================================
    if [ -n "$PYTHON_TARGET" ]; then
        # Executamos injetando o array nativamente. Sem "eval", logo sem erro de escape!
        sudo bash -c 'source "$1"; shift; exec "$@"' -- "$PYTHON_TARGET" "${IPED_CMD[@]}"
    else
        sudo "${IPED_CMD[@]}"
    fi

    if [ $? -ne 0 ]; then
        echo "ERRO: O processamento do IPED falhou."
        zenity --error --text="Ocorreu um erro durante o processamento do IPED.\nVerifique o log neste terminal ou em $LOG_FILE_PATH\n\nVocê pode tentar executar novamente e escolher 'Continuar Processamento Anterior'." --width=500
        exit 4
    fi
fi

echo "Processamento IPED finalizado com sucesso."
echo "---------------------------------------------"

# 6. Pós-Processamento
if ! $CONTINUE_PROCESSING; then
    run_post_processing
    echo "Pós-processamento concluído."
else
    echo "Pós-processamento ignorado (modo continue)."
fi

echo "Caso disponível em: $OUTPUT_DIR"
echo "============================================="