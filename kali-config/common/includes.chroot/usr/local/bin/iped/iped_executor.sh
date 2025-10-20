#!/bin/bash
#
# iped_executor.sh
# Script "motor" para execução do IPED.
# Recebe parâmetros do launcher Python e executa a lógica de processamento.
# (Versão que usa o perfil original ao continuar processamento)
#

# --- Constantes ---
IPED_DIR="/usr/local/bin/iped"
JAVA_CMD_BASE="java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped.jar"
OUTPUT_DIR_DESKTOP="/home/kali/Desktop/IPED-CASO"
OUTPUT_DIR_TRIAGE_BASE="/home/kali/Desktop/triage"
OUTPUT_DIR_TRIAGE_CASE="$OUTPUT_DIR_TRIAGE_BASE/IPED-CASO"
COMMAND_LOG_FILE="/home/kali/Desktop/iped_comando_executado.log" # Arquivo de log no Desktop

# --- Variáveis Globais ---
CONTINUE_PROCESSING=false # Flag para indicar se vamos continuar um processamento
RECOVERED_CMD=""          # Armazena o comando recuperado do log para --continue

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
            ln -sf /dislocker/bitlocker_$disk_basename/dislocker-file /dislocker/dislocker-file_$disk_basename.dd
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
            if ! mount -o rw $triage_part_device $OUTPUT_DIR_TRIAGE_BASE; then
                echo "ERRO: Falha ao montar a partição Triage em $OUTPUT_DIR_TRIAGE_BASE. Verifique permissões ou sistema de arquivos."
                TRIAGE_PARTITION_FOUND=false
                zenity --error --text="Falha ao montar a partição Triage.\nO SWAP não será criado e o caso será salvo no Desktop." --timeout=10
                OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
                DESKTOP_FILE="IPED-Caso.desktop"
                LOG_FILE_OPT=""
                KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt"
            fi
        fi

        if $TRIAGE_PARTITION_FOUND; then
            LOG_FILE_OPT="-log $OUTPUT_DIR_TRIAGE_BASE/IPED-Processamento-$(date +%y%m%d%H%M).log"
            if test -f "$OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"; then
                KEYWORD_FILE_OPT="-l $OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"
            else
                KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt"
            fi

            cp "$IPED_DIR/LocalConfig-triage.txt" "$IPED_DIR/LocalConfig.txt"

            if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
                if [ "$(cat /proc/swaps | wc -l)" -le 1 ]; then
                    local swap_file_path="$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                    if test -f "$swap_file_path"; then
                         echo "Arquivo SWAP encontrado ($swap_file_path). Ativando..."
                         swapon "$swap_file_path"
                         if [ $? -ne 0 ]; then
                             echo "Aviso: Falha ao ativar SWAP existente. Tentando recriar..."
                             swapoff "$swap_file_path" &> /dev/null
                             rm -f "$swap_file_path"
                         else
                              local create_swap=false
                         fi
                    fi

                    if [ ! -f "$swap_file_path" ] || [ "$create_swap" != "false" ]; then
                         echo "Criando arquivo de memoria virtual swap..."
                         available_kb=$(df -k "$OUTPUT_DIR_TRIAGE_BASE" | tail -n 1 | awk '{print $4}')
                         available_kb=${available_kb:-0}

                         if (( available_kb < 102400 )); then
                              echo "Aviso: Espaço livre insuficiente (< 100MB) na partição Triage para criar SWAP."
                         else
                              target_kb=$((available_kb / 10))
                              max_kb=$((10 * 1024 * 1024))

                              if (( target_kb > max_kb )); then
                                  swap_size_kb=$max_kb
                              else
                                  swap_size_kb=$target_kb
                              fi

                              swap_size_mb=$((swap_size_kb / 1024))
                              swap_size_gb=$(echo "scale=1; $swap_size_mb / 1024" | bc)

                              echo "Espaço disponível na partição Triage: $((available_kb / 1024 / 1024)) GB"
                              echo "Tamanho alvo do SWAP (10% ou 10GB max): ${swap_size_gb} GB (${swap_size_mb} MB)"

                              if truncate -s "${swap_size_mb}M" "$swap_file_path"; then
                                   mkswap "$swap_file_path"
                                   swapon "$swap_file_path"
                                   if [ $? -ne 0 ]; then
                                       echo "ERRO: Falha ao ativar o SWAP recém-criado!"
                                       rm -f "$swap_file_path"
                                   fi
                              else
                                   echo "ERRO: Falha ao criar o arquivo SWAP com truncate."
                              fi
                         fi
                    fi
                else
                    echo "Memoria SWAP ja esta habilitada."
                fi
            fi
        fi

    else # Se a partição Triage NÃO foi encontrada inicialmente
        echo "Nenhuma partição IPED-TRIAGE encontrada. Usando Desktop."
        OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
        DESKTOP_FILE="IPED-Caso.desktop"
        LOG_FILE_OPT=""
        KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt"

        if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
            echo "AVISO: Perfil '$PROFILE' sem partição Triage pode causar falta de memória."
            zenity --warning --title="Partição Triage Não Encontrada" \
                   --text="Para o perfil '$PROFILE', é altamente recomendável usar uma partição 'IPED-TRIAGE' para armazenar o caso e criar um arquivo de SWAP.\n\nContinuar pode causar instabilidade ou falta de memória." \
                   --width=400
        fi
    fi

    echo "Diretório de saída definido como: $OUTPUT_DIR"

    # --- VERIFICA SE O DIRETÓRIO JÁ EXISTE ---
    if [ -d "$OUTPUT_DIR" ]; then
        echo "Diretório de saída '$OUTPUT_DIR' já existe."
        if zenity --question --title="Caso Existente Encontrado" \
            --text="Um caso IPED já existe no diretório de saída:\n<b>$OUTPUT_DIR</b>\n\nO que você deseja fazer?" \
            --ok-label="Processar Novamente (Apagar existente)" \
            --cancel-label="Continuar Processamento Anterior" \
            --width=450;
        then
            # Usuário escolheu "Processar Novamente" (OK)
            echo "Usuário escolheu processar novamente. Apagando diretório existente..."
            rm -rf "$OUTPUT_DIR"
            if [ $? -ne 0 ]; then
                zenity --error --text="Falha ao apagar o diretório '$OUTPUT_DIR'.\nVerifique as permissões."
                exit 6
            fi
            mkdir -p "$OUTPUT_DIR"
            CONTINUE_PROCESSING=false
        else
            # Usuário escolheu "Continuar" (Cancel)
            echo "Usuário escolheu continuar o processamento anterior."
            CONTINUE_PROCESSING=true
            # --- MODIFICAÇÃO: Recuperar comando e perfil original ---
            if [ -f "$COMMAND_LOG_FILE" ]; then
                 local escaped_output_dir=$(sed 's/[&/\]/\\&/g' <<<"$OUTPUT_DIR")
                 RECOVERED_CMD=$(grep "$escaped_output_dir" "$COMMAND_LOG_FILE" | tail -n 1 | sed 's/^\[.*\] Executando: //')

                 if [ -z "$RECOVERED_CMD" ]; then
                      zenity --error --text="Não foi possível encontrar o comando anterior para '$OUTPUT_DIR' no log.\nNão é possível continuar. Verifique o arquivo '$COMMAND_LOG_FILE'."
                      exit 7
                 else
                      echo "Comando anterior recuperado: $RECOVERED_CMD"
                      # Extrai o perfil original do comando recuperado
                      local original_profile=$(echo "$RECOVERED_CMD" | grep -o '\-profile [^ ]*' | awk '{print $2}')
                      if [ -z "$original_profile" ]; then
                          zenity --error --text="Não foi possível extrair o perfil do comando anterior.\nNão é possível continuar."
                          exit 8
                      fi
                      # *** SOBRESCREVE O PROFILE ATUAL COM O ORIGINAL ***
                      echo "Usando o perfil original do caso: $original_profile (Seleção atual '$PROFILE' ignorada)."
                      PROFILE=$original_profile
                      # Adiciona a flag --continue (se já não existir)
                      if ! echo "$RECOVERED_CMD" | grep -q -- '--continue'; then
                           RECOVERED_CMD+=" --continue"
                      fi
                      echo "Comando final para continuar: $RECOVERED_CMD"
                 fi
            else
                 zenity --error --text="Arquivo de log '$COMMAND_LOG_FILE' não encontrado.\nNão é possível recuperar o comando anterior para continuar."
                 exit 7
            fi
            # --- FIM DA MODIFICAÇÃO ---
        fi
    else
        # Diretório não existe, cria normalmente
        mkdir -p "$OUTPUT_DIR"
        CONTINUE_PROCESSING=false
    fi

    echo "Diretório de saída final: $OUTPUT_DIR"
}


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
            ldmtool create all &> /dev/null
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
                        ln -sf "/vss/$line/$vss" "/vss_iped/$line-$vss.dd"
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
        # Armazena o profile selecionado pelo usuário em uma variável temporária
        --profile) SELECTED_PROFILE="$2"; shift ;;
        --target) TARGET_MODE="$2"; shift ;;
        --path) MANUAL_PATH="$2"; shift ;;
        *) echo "Parâmetro desconhecido: $1"; exit 1 ;;
    esac
    shift
done
# Define o PROFILE global com o selecionado (pode ser sobrescrito pelo modo continue)
PROFILE=$SELECTED_PROFILE

echo "============================================="
echo "      INICIALIZANDO MOTOR IPED"
echo "============================================="
echo "Perfil selecionado inicialmente: $PROFILE"
echo "Alvo: $TARGET_MODE"
[ ! -z "$MANUAL_PATH" ] && echo "Caminho: $MANUAL_PATH"
echo "---------------------------------------------"


# 2. Setup
cd "$IPED_DIR" || { echo "Erro: Diretório $IPED_DIR não encontrado."; exit 1; }
mplayer &> /dev/null # Bugfix

# 3. Preparação
setup_output_dir # Define $OUTPUT_DIR, $CONTINUE_PROCESSING e sobrescreve $PROFILE se for continuar

# Só constrói a string de alvos se NÃO for continuar
if ! $CONTINUE_PROCESSING; then
     build_target_string # Define $TARGET_STRING
fi


# 4. Construção e Log do Comando
if $CONTINUE_PROCESSING; then
    # Usa o comando recuperado e já modificado (com --continue e profile original)
    FINAL_CMD=$RECOVERED_CMD
    echo "Usando comando recuperado para continuar (com perfil '$PROFILE'):"
else
    # Constrói o comando normalmente para um novo processamento
    FINAL_CMD="$JAVA_CMD_BASE -o $OUTPUT_DIR -profile $PROFILE $LOG_FILE_OPT $KEYWORD_FILE_OPT $TARGET_STRING"
    echo "========================================================"
    echo "COMANDO FINAL A SER EXECUTADO:"
    echo "$FINAL_CMD"
    echo "========================================================"

    # --- LOG DO COMANDO ---
    echo "Registrando comando em $COMMAND_LOG_FILE..."
    mkdir -p "$(dirname "$COMMAND_LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executando: $FINAL_CMD" >> "$COMMAND_LOG_FILE"
    chown kali:kali "$COMMAND_LOG_FILE" || echo "Aviso: Falha ao mudar proprietário do arquivo de log do comando."
    # --- FIM DO LOG ---
fi

echo "Iniciando IPED... Isso pode levar muito tempo."

# 5. Execução
$FINAL_CMD

if [ $? -ne 0 ]; then
    echo "ERRO: O processamento do IPED falhou."
    if ! $CONTINUE_PROCESSING; then
         zenity --error --text="Ocorreu um erro durante o processamento do IPED.\nVerifique o log neste terminal ou em $LOG_FILE_OPT\n\nVocê pode tentar executar novamente e escolher 'Continuar Processamento Anterior'." --width=500
    else
         zenity --error --text="Ocorreu um erro durante a continuação do processamento do IPED.\nVerifique o log neste terminal ou em $LOG_FILE_OPT" --width=500
    fi
    exit 4
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