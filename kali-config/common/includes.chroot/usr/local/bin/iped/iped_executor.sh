#!/bin/bash
#
# iped_executor.sh
# Script "motor" para execução do IPED.
# Recebe parâmetros do launcher Python e executa a lógica de processamento.
# (Versão com lógica de swap/aviso unificada para triage e csam_triage)
#

# --- Constantes ---
IPED_DIR="/usr/local/bin/iped"
JAVA_CMD_BASE="java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped.jar"
OUTPUT_DIR_DESKTOP="/home/kali/Desktop/IPED-CASO"
OUTPUT_DIR_TRIAGE_BASE="/home/kali/Desktop/triage"
OUTPUT_DIR_TRIAGE_CASE="$OUTPUT_DIR_TRIAGE_BASE/IPED-CASO"

# --- Funções de Lógica ---

# Função para lidar com BitLocker (AINDA USA ZENITY para senhas)
handle_bitlocker() {
    local disk_device=$1
    local cmdline_ref=$2 # Passa o nome da variável que armazena os discos
    local root_system=$3

    local disk_basename=$(basename "$disk_device")
    if ! echo "$disk_basename" | grep -q "$root_system"; then
        echo "Detectado bitlocker em $disk_device"
        mkdir -p /dislocker/bitlocker_$disk_basename

        dislocker -V $disk_device -- /dislocker/bitlocker_$disk_basename -r
        if test -f /dislocker/bitlocker_$disk_basename/dislocker-file; then
            echo "Bitlocker (sem senha) montado."
            ln -sf /dislocker/bitlocker_$disk_basename/dislocker-file /dislocker/dislocker-file_$disk_basename.dd # Usar -sf para forçar sobrescrita se o link já existir
            eval "$cmdline_ref+=\" -d /dislocker/dislocker-file_$disk_basename.dd\""
        else
            while true; do
                BITLOCKER_INFO=('', '')
                while read line ; do
                    [[ $line =~ "Description:" ]] && BITLOCKER_INFO[0]=$line
                    [[ $line =~ "VMK protected with recovery passphrase" ]] && BITLOCKER_INFO[1]=${previousline^^}
                    previousline=$line
                done <<< "$(cryptsetup bitlkDump $disk_device)"

                bitlocker_pass=$(zenity --entry --title="Detectado BitLocker!" \
                    --text="Partição criptografada com Bitlocker em $disk_device.\nDigite a senha de acesso ou a chave de recuperação:\n\n${BITLOCKER_INFO[0]}\n${BITLOCKER_INFO[1]}" \
                    --entry-text "ChaveDeRecuperacao" --width=500)

                if [ $? = 0 ]; then
                    dislocker -V $disk_device -p"$bitlocker_pass" -- /dislocker/bitlocker_$disk_basename -r
                    if test -f /dislocker/bitlocker_$disk_basename/dislocker-file; then
                        echo "Bitlocker decifrado com chave de recuperação."
                        ln -sf /dislocker/bitlocker_$disk_basename/dislocker-file /dislocker/dislocker-file_$disk_basename.dd
                        eval "$cmdline_ref+=\" -d /dislocker/dislocker-file_$disk_basename.dd\""
                        break
                    else
                        dislocker -V $disk_device --user-password="$bitlocker_pass" -- /dislocker/bitlocker_$disk_basename -r
                        if test -f /dislocker/bitlocker_$disk_basename/dislocker-file; then
                            echo "Bitlocker decifrado com senha de usuário."
                            ln -sf /dislocker/bitlocker_$disk_basename/dislocker-file /dislocker/dislocker-file_$disk_basename.dd
                            eval "$cmdline_ref+=\" -d /dislocker/dislocker-file_$disk_basename.dd\""
                            break
                        else
                            zenity --error --title="Erro de Chave BitLocker!" --text="A chave ou senha fornecida não decifrou a unidade." --width=300 --timeout=10
                        fi
                    fi
                else
                    echo "Usuário cancelou a inserção de senha do Bitlocker."
                    break # Cancela
                fi
            done
        fi
    fi
}

# Lógica para encontrar e montar partição de triagem
# --- FUNÇÃO MODIFICADA ---
setup_output_dir() {
    echo "Configurando diretório de saída..."
    TRIAGE_PARTITION_FOUND=false
    local triage_part_device=""

    local root_system=$(cat /proc/mounts | grep /run/live/medium | awk '{print $1}')
    local root_system_triage=${root_system:5:${#root_system}-6}
    [ -z "$root_system_triage" ] && root_system_triage='null'

    while read line ; do
        local part=$(echo "$line" | awk '{print $1}')
        if echo "$part" | grep -q "$root_system_triage"; then
           if blkid /dev/$part | grep -q 'IPED-TRIAGE'; then
	           triage_part_device="/dev/$part"
               TRIAGE_PARTITION_FOUND=true
	           break
	       fi
        fi
    done <<< "$(lsblk -l | grep part)"

    if $TRIAGE_PARTITION_FOUND; then
        echo "Partição IPED-TRIAGE encontrada em $triage_part_device"
        OUTPUT_DIR=$OUTPUT_DIR_TRIAGE_CASE
        DESKTOP_FILE="IPED-Caso-triage.desktop"

        if ! findmnt --mountpoint $OUTPUT_DIR_TRIAGE_BASE &> /dev/null; then
            echo "Montando partição triage em $OUTPUT_DIR_TRIAGE_BASE"
            mkdir -p $OUTPUT_DIR_TRIAGE_BASE
            mount -o rw $triage_part_device $OUTPUT_DIR_TRIAGE_BASE
        fi

        LOG_FILE_OPT="-log $OUTPUT_DIR_TRIAGE_BASE/IPED-Processamento-$(date +%y%m%d%H%M).log"
        if test -f "$OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"; then
	        KEYWORD_FILE_OPT="-l $OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"
        else
            KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt" # Fallback
	    fi

	    cp "$IPED_DIR/LocalConfig-triage.txt" "$IPED_DIR/LocalConfig.txt"

        # --- Lógica de SWAP (Agora para triage E csam_triage) ---
        if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
            if [ "$(cat /proc/swaps | wc -l)" -le 1 ]; then
                # Verifica se já existe um swapfile na partição antes de criar
                if test -f "$OUTPUT_DIR_TRIAGE_BASE/swapfile"; then
                     echo "Arquivo SWAP encontrado. Ativando..."
                     swapon "$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                else
                     echo "Criando arquivo de memoria virtual swap (10GB)..."
                     truncate -s 10G "$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                     mkswap "$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                     swapon "$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                fi
            else
                echo "Memoria SWAP ja esta habilitada."
            fi
        fi
        # --- Fim da lógica de SWAP ---

    else
        echo "Nenhuma partição IPED-TRIAGE encontrada. Usando Desktop."
        OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
        DESKTOP_FILE="IPED-Caso.desktop"
        LOG_FILE_OPT="" # Sem log específico
        KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt"

        # --- Aviso (Agora para triage E csam_triage) ---
        if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
            echo "AVISO: Perfil '$PROFILE' sem partição Triage pode causar falta de memória."
            zenity --warning --title="Partição Triage Não Encontrada" \
                   --text="Para o perfil '$PROFILE', é altamente recomendável usar uma partição 'IPED-TRIAGE' para armazenar o caso e criar um arquivo de SWAP.\n\nContinuar pode causar instabilidade ou falta de memória." \
                   --width=400
        fi
        # --- Fim do Aviso ---
    fi

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    echo "Diretório de saída: $OUTPUT_DIR"
}
# --- FIM DA FUNÇÃO MODIFICADA ---


# Monta o alvo de processamento (parâmetro -d)
build_target_string() {
    TARGET_STRING=""
    local root_system=$(cat /proc/mounts | grep /run/live/medium | awk '{print $1}')

    case $TARGET_MODE in
        "all_disks")
            echo "Construindo string de alvos: Discos"

            # 1. Discos Físicos
            while read line ; do
                local disk=$(echo "$line" | awk '{print $1}')
                if ! echo "$root_system" | grep -q "$disk"; then
                  TARGET_STRING+=" -d /dev/$disk"
                fi
            done <<< "$(lsblk -l | grep disk)"

            # 2. LDM (RAID Windows)
            ldmtool create all &> /dev/null # Silencia a saída
            while read line ; do
                local disk=$(echo "$line" | awk '{print $1}')
                if ! echo "$TARGET_STRING" | grep -q "$disk"; then
                  TARGET_STRING+=" -d /dev/mapper/$disk"
                fi
            done <<< "$(lsblk -l | grep '\dm\b')"

            # 3. VSS
            if [ -d "/vss" ]; then
                echo "Verificando VSS..."
                mkdir -p /vss_iped
                while read line ; do
                    for vss in $(ls /vss/$line 2>/dev/null); do
                        echo "Achou vss: /vss/$line/$vss"
                        ln -sf "/vss/$line/$vss" "/vss_iped/$line-$vss.dd" # Usar -sf
                        TARGET_STRING+=" -d /vss_iped/$line-$vss.dd"
                    done
                done <<< "$(ls /vss/ 2>/dev/null)"
            fi

            # 4. BitLocker
            echo "Verificando Bitlocker..."
            mkdir -p /dislocker
            while read line ; do
                if [ ! -z "$line" ]; then
                    handle_bitlocker "$line" TARGET_STRING "$root_system"
                fi
            done <<< "$(dislocker-find)"
            ;;

        "mounted_files")
            echo "Construindo string de alvos: Arquivos Montados"
            if [ -f "/home/kali/mount_disks.sh" ]; then
                /home/kali/mount_disks.sh
            fi
            TARGET_STRING="-d /media/"
            ;;

        "manual_dir")
            echo "Construindo string de alvos: Seleção Manual"
            if [ -z "$MANUAL_PATH" ]; then
                echo "Erro: --target=manual_dir mas --path não foi fornecido."
                exit 5
            fi
            TARGET_STRING="-d \"$MANUAL_PATH\""
            ;;
    esac

    if [ -z "$TARGET_STRING" ]; then
        echo "Erro: Nenhum alvo de processamento foi determinado."
        zenity --error --text="Nenhum alvo de processamento foi determinado. Verifique os discos."
        exit 3
    fi
}

# Executa tarefas pós-processamento
run_post_processing() {
    echo "Iniciando pós-processamento..."
    cp "$IPED_DIR/Ferramenta_de_Pesquisa.sh" "$OUTPUT_DIR/"
    cp "$IPED_DIR/$DESKTOP_FILE" "/home/kali/Desktop/IPED-Caso.desktop"

    # Define o proprietário como 'kali'
    local output_parent_dir=$(dirname "$OUTPUT_DIR")
    chown -R kali:kali "$output_parent_dir" || echo "Aviso: Falha ao mudar proprietário de $output_parent_dir"
    chown kali:kali "/home/kali/Desktop/IPED-Caso.desktop" || echo "Aviso: Falha ao mudar proprietário do atalho"

    cd "$OUTPUT_DIR"
    if [ -f "./Ferramenta_de_Pesquisa.sh" ]; then
        # Tenta executar como usuário 'kali' se o script não precisar de root
        if grep -q "sudo" ./Ferramenta_de_Pesquisa.sh; then
             ./Ferramenta_de_Pesquisa.sh
        else
             sudo -u kali ./Ferramenta_de_Pesquisa.sh
        fi
    else
        echo "Erro: Ferramenta_de_Pesquisa.sh não encontrada."
    fi
}

# --- Função Principal (Main) ---

# 1. Parse dos argumentos
if [ $# -eq 0 ]; then
    echo "Erro: Este script deve ser chamado pelo iped_launcher.py"
    echo "Uso: $0 --profile <p> --target <t> [--path <path>]"
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --profile) PROFILE="$2"; shift ;;
        --target) TARGET_MODE="$2"; shift ;;
        --path) MANUAL_PATH="$2"; shift ;;
        *) echo "Parâmetro desconhecido: $1"; exit 1 ;;
    esac
    shift
done

echo "============================================="
echo "      INICIALIZANDO MOTOR IPED"
echo "============================================="
echo "Perfil: $PROFILE"
echo "Alvo: $TARGET_MODE"
[ ! -z "$MANUAL_PATH" ] && echo "Caminho: $MANUAL_PATH"
echo "---------------------------------------------"


# 2. Setup
cd "$IPED_DIR" || { echo "Erro: Diretório $IPED_DIR não encontrado."; exit 1; }
mplayer &> /dev/null # Bugfix

# 3. Preparação
setup_output_dir
build_target_string

# 4. Execução
FINAL_CMD="$JAVA_CMD_BASE -o $OUTPUT_DIR -profile $PROFILE $LOG_FILE_OPT $KEYWORD_FILE_OPT $TARGET_STRING"

echo "========================================================"
echo "COMANDO FINAL A SER EXECUTADO:"
echo "$FINAL_CMD"
echo "========================================================"
echo "Iniciando IPED... Isso pode levar muito tempo."

# Executa o comando
$FINAL_CMD

if [ $? -ne 0 ]; then
    echo "ERRO: O processamento do IPED falhou."
    zenity --error --text="Ocorreu um erro durante o processamento do IPED.\nVerifique o log neste terminal ou em $LOG_FILE_OPT"
    exit 4
fi

echo "Processamento IPED finalizado com sucesso."
echo "---------------------------------------------"

# 5. Pós-Processamento
run_post_processing

echo "Pós-processamento concluído."
echo "Caso disponível em: $OUTPUT_DIR"
echo "============================================="