#!/bin/bash
#
# iped_executor.sh
# Script "motor" para execução do IPED.
# Recebe parâmetros do launcher Python e executa a lógica de processamento.
# (Versão com sudo rm -rf incondicional ao apagar caso existente)
#

# --- Constantes ---
IPED_DIR="/usr/local/bin/iped"
JAVA_CMD_BASE="sudo java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped.jar"
OUTPUT_DIR_DESKTOP="/home/kali/Desktop/IPED-CASO"
OUTPUT_DIR_TRIAGE_BASE="/home/kali/Desktop/triage"
OUTPUT_DIR_TRIAGE_CASE="$OUTPUT_DIR_TRIAGE_BASE/IPED-CASO"
COMMAND_LOG_FILE="/home/kali/Desktop/iped_comando_executado.log"

# --- Variáveis Globais ---
CONTINUE_PROCESSING=false
RECOVERED_CMD=""
KALI_UID=1000 # UID Padrão do usuário 'kali'
KALI_GID=1000 # GID Padrão do usuário 'kali'

# --- Funções de Lógica ---

# Função para lidar com BitLocker
handle_bitlocker() {
    local disk_device=$1
    local cmdline_ref=$2
    local root_system=$3
    local disk_basename=$(basename "$disk_device")

    if ! echo "$disk_basename" | grep -q "$root_system"; then
        echo "Detectado bitlocker em $disk_device"
        sudo mkdir -p /dislocker/bitlocker_$disk_basename

        sudo dislocker -V $disk_device -- /dislocker/bitlocker_$disk_basename -r
        if sudo test -f /dislocker/bitlocker_$disk_basename/dislocker-file; then
            echo "Bitlocker (sem senha) montado."
            sudo ln -sf /dislocker/bitlocker_$disk_basename/dislocker-file /dislocker/dislocker-file_$disk_basename.dd
            eval "$cmdline_ref+=\" -d /dislocker/dislocker-file_$disk_basename.dd\""
        else
            while true; do
                BITLOCKER_INFO=('', '')
                while read line ; do
                    [[ $line =~ "Description:" ]] && BITLOCKER_INFO[0]=$line
                    [[ $line =~ "VMK protected with recovery passphrase" ]] && BITLOCKER_INFO[1]=${previousline^^}
                    previousline=$line
                done <<< "$(sudo cryptsetup bitlkDump $disk_device)"

                bitlocker_pass=$(zenity --entry --title="Detectado BitLocker!" \
                    --text="Partição criptografada com Bitlocker em $disk_device.\nDigite a senha de acesso ou a chave de recuperação:\n\n${BITLOCKER_INFO[0]}\n${BITLOCKER_INFO[1]}" \
                    --entry-text "ChaveDeRecuperacao" --width=500)

                if [ $? = 0 ]; then
                    sudo dislocker -V $disk_device -p"$bitlocker_pass" -- /dislocker/bitlocker_$disk_basename -r
                    if sudo test -f /dislocker/bitlocker_$disk_basename/dislocker-file; then
                        echo "Bitlocker decifrado com chave de recuperação."
                        sudo ln -sf /dislocker/bitlocker_$disk_basename/dislocker-file /dislocker/dislocker-file_$disk_basename.dd
                        eval "$cmdline_ref+=\" -d /dislocker/dislocker-file_$disk_basename.dd\""
                        break
                    else
                        sudo dislocker -V $disk_device --user-password="$bitlocker_pass" -- /dislocker/bitlocker_$disk_basename -r
                        if sudo test -f /dislocker/bitlocker_$disk_basename/dislocker-file; then
                            echo "Bitlocker decifrado com senha de usuário."
                            sudo ln -sf /dislocker/bitlocker_$disk_basename/dislocker-file /dislocker/dislocker-file_$disk_basename.dd
                            eval "$cmdline_ref+=\" -d /dislocker/dislocker-file_$disk_basename.dd\""
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
# --- FUNÇÃO MODIFICADA (Lógica de rm e mkdir) ---
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
           if sudo blkid /dev/$part | grep -q 'IPED-TRIAGE'; then
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

        # Garante que o diretório base exista (sem sudo)
        if [ ! -d "$OUTPUT_DIR_TRIAGE_BASE" ]; then
             echo "Criando diretório base de triagem: $OUTPUT_DIR_TRIAGE_BASE"
             mkdir -p "$OUTPUT_DIR_TRIAGE_BASE"
        fi

        # Verifica se JÁ está montado
        if findmnt --mountpoint $OUTPUT_DIR_TRIAGE_BASE &> /dev/null; then
             echo "Partição Triage já está montada em $OUTPUT_DIR_TRIAGE_BASE."
             if [ "$(stat -c '%u' "$OUTPUT_DIR_TRIAGE_BASE")" != "$KALI_UID" ]; then
                  echo "Ponto de montagem não pertence ao usuário kali. Tentando remontar com opções corretas..."
                  sudo umount "$OUTPUT_DIR_TRIAGE_BASE" &> /dev/null
                  echo "Montando $triage_part_device em $OUTPUT_DIR_TRIAGE_BASE com sudo e uid/gid..."
                  if ! sudo mount -o rw,uid=$KALI_UID,gid=$KALI_GID $triage_part_device $OUTPUT_DIR_TRIAGE_BASE; then
                       echo "ERRO: Falha ao remontar a partição Triage com uid/gid."
                       TRIAGE_PARTITION_FOUND=false
                       zenity --error --text="Falha ao ajustar permissões da partição Triage.\nO SWAP não será criado e o caso será salvo no Desktop." --timeout=10
                       OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
                       DESKTOP_FILE="IPED-Caso.desktop"
                       LOG_FILE_OPT=""
                       KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt"
                  fi
             fi
        else
            # MONTAGEM COM SUDO e UID/GID
            echo "Montando $triage_part_device em $OUTPUT_DIR_TRIAGE_BASE com sudo e uid=$KALI_UID,gid=$KALI_GID..."
            if ! sudo mount -o rw,uid=$KALI_UID,gid=$KALI_GID $triage_part_device $OUTPUT_DIR_TRIAGE_BASE; then
                echo "ERRO: Falha ao montar a partição Triage com sudo e uid/gid."
                TRIAGE_PARTITION_FOUND=false
                zenity --error --text="Falha ao montar a partição Triage.\nO SWAP não será criado e o caso será salvo no Desktop." --timeout=10
                OUTPUT_DIR=$OUTPUT_DIR_DESKTOP
                DESKTOP_FILE="IPED-Caso.desktop"
                LOG_FILE_OPT=""
                KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt"
            fi
        fi


        # Só continua a lógica de Triage se a partição foi encontrada E montada
        if $TRIAGE_PARTITION_FOUND; then
            LOG_FILE_OPT="-log $OUTPUT_DIR_TRIAGE_BASE/IPED-Processamento-$(date +%y%m%d%H%M).log"
            # test sem sudo, pois kali deve ser dono
            if test -f "$OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"; then
                KEYWORD_FILE_OPT="-l $OUTPUT_DIR_TRIAGE_BASE/palavras-chave.txt"
            else
                KEYWORD_FILE_OPT="-l $IPED_DIR/palavras-chave.txt"
            fi
            # cp com sudo
            sudo cp "$IPED_DIR/LocalConfig-triage.txt" "$IPED_DIR/LocalConfig.txt"

            # Lógica de SWAP
            if [ "$PROFILE" == "csam_triage" ] || [ "$PROFILE" == "triage" ]; then
                if [ "$(cat /proc/swaps | wc -l)" -le 1 ]; then
                    local swap_file_path="$OUTPUT_DIR_TRIAGE_BASE/swapfile"
                    # test sem sudo
                    if test -f "$swap_file_path"; then
                         echo "Arquivo SWAP encontrado ($swap_file_path). Ativando..."
                         sudo swapon "$swap_file_path" # Precisa de sudo
                         if [ $? -ne 0 ]; then
                             echo "Aviso: Falha ao ativar SWAP existente. Tentando recriar..."
                             sudo swapoff "$swap_file_path" &> /dev/null # Precisa de sudo
                             rm -f "$swap_file_path" # rm sem sudo
                         else
                              local create_swap=false
                         fi
                    fi

                    if [ ! -f "$swap_file_path" ] || [ "$create_swap" != "false" ]; then
                         echo "Criando arquivo de memoria virtual swap..."
                         # df sem sudo
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

                              # truncate sem sudo
                              if truncate -s "${swap_size_mb}M" "$swap_file_path"; then
                                   # mkswap e swapon com sudo
                                   sudo mkswap "$swap_file_path"
                                   sudo swapon "$swap_file_path"
                                   if [ $? -ne 0 ]; then
                                       echo "ERRO: Falha ao ativar o SWAP recém-criado!"
                                       rm -f "$swap_file_path" # rm sem sudo
                                   fi
                              else
                                   echo "ERRO: Falha ao criar o arquivo SWAP com truncate (verifique permissões em $OUTPUT_DIR_TRIAGE_BASE)."
                              fi
                         fi
                    fi
                else
                    echo "Memoria SWAP ja esta habilitada."
                fi
            fi # Fim da lógica SWAP
        fi # Fim do if $TRIAGE_PARTITION_FOUND (pós-montagem)

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
            echo "Usuário escolheu processar novamente. Apagando diretório existente..."
            # --- MODIFICAÇÃO: Sempre usar sudo rm ---
            sudo rm -rf "$OUTPUT_DIR"
            # --- FIM DA MODIFICAÇÃO ---
            if [ $? -ne 0 ]; then
                zenity --error --text="Falha ao apagar o diretório '$OUTPUT_DIR'.\nVerifique as permissões."
                exit 6
            fi
            # Usa sudo para criar e ajustar dono, mais seguro
            sudo mkdir -p "$OUTPUT_DIR"
            sudo chown $KALI_UID:$KALI_GID "$OUTPUT_DIR"
            CONTINUE_PROCESSING=false
        else
            echo "Usuário escolheu continuar o processamento anterior."
            CONTINUE_PROCESSING=true
            if [ -f "$COMMAND_LOG_FILE" ]; then
                 local escaped_output_dir=$(sed 's#[&/\]#\\&#g' <<<"$OUTPUT_DIR")
                 local original_cmd=$(grep "$escaped_output_dir" "$COMMAND_LOG_FILE" | tail -n 1 | sed 's/^\[.*\] Executando: //')

                 if [ -z "$original_cmd" ]; then
                      zenity --error --text="Não foi possível encontrar o comando anterior para '$OUTPUT_DIR' no log." ; exit 7
                 else
                      echo "Comando anterior recuperado: $original_cmd"
                      local original_profile=$(echo "$original_cmd" | grep -o '\-profile [^ ]*' | awk '{print $2}')
                      if [ -z "$original_profile" ]; then
                          zenity --error --text="Não foi possível extrair o perfil do comando anterior." ; exit 8
                      fi
                      echo "Usando o perfil original do caso: $original_profile (Seleção atual '$PROFILE' ignorada)."
                      PROFILE=$original_profile

                      if echo "$original_cmd" | grep -q -- "-jar iped.jar"; then
                          if ! echo "$original_cmd" | grep -q -- '--continue'; then
                               RECOVERED_CMD=$(echo "$original_cmd" | sed 's/-jar iped\.jar/-jar iped.jar --continue/')
                               echo "Comando final para continuar: $RECOVERED_CMD"
                          else
                               echo "Flag --continue já presente. Usando como está." ; RECOVERED_CMD="$original_cmd"
                          fi
                      else
                           zenity --error --text="Formato de comando inesperado no log: $original_cmd" ; exit 9
                      fi
                 fi
            else
                 zenity --error --text="Arquivo de log '$COMMAND_LOG_FILE' não encontrado." ; exit 7
            fi
        fi
    else
        # Diretório não existe, cria (com sudo e ajusta dono)
        sudo mkdir -p "$OUTPUT_DIR"
        sudo chown $KALI_UID:$KALI_GID "$OUTPUT_DIR"
        CONTINUE_PROCESSING=false
    fi

    # Garante que o diretório de saída existe e pertence a kali
    if [ ! -d "$OUTPUT_DIR" ] || [ "$(stat -c '%u' "$OUTPUT_DIR")" != "$KALI_UID" ]; then
        zenity --error --text="Falha ao criar ou definir permissões para o diretório de saída: $OUTPUT_DIR"
        exit 10
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

            # 1. Discos Físicos (lsblk não precisa de sudo)
            while read line ; do
                local disk=$(echo "$line" | awk '{print $1}')
                if ! echo "$root_system" | grep -q "$disk"; then
                  TARGET_STRING+=" -d /dev/$disk"
                fi
            done <<< "$(lsblk -l | grep disk)"

            # 2. LDM (RAID Windows) - Precisa de sudo
            sudo ldmtool create all &> /dev/null
            while read line ; do
                local disk=$(echo "$line" | awk '{print $1}')
                if ! echo "$TARGET_STRING" | grep -q "$disk"; then
                  TARGET_STRING+=" -d /dev/mapper/$disk"
                fi
            done <<< "$(lsblk -l | grep '\dm\b')"

            # 3. VSS - Precisa de sudo
            if [ -d "/vss" ]; then
                echo "Verificando VSS..."
                sudo mkdir -p /vss_iped
                while read line ; do
                    for vss in $(sudo ls /vss/$line 2>/dev/null); do
                        echo "Achou vss: /vss/$line/$vss"
                        sudo ln -sf "/vss/$line/$vss" "/vss_iped/$line-$vss.dd"
                        TARGET_STRING+=" -d /vss_iped/$line-$vss.dd"
                    done
                done <<< "$(sudo ls /vss/ 2>/dev/null)"
            fi

            # 4. BitLocker - handle_bitlocker já usa sudo internamente
            echo "Verificando Bitlocker..."
            sudo mkdir -p /dislocker
            while read line ; do
                if [ ! -z "$line" ]; then
                    handle_bitlocker "$line" TARGET_STRING "$root_system"
                fi
            done <<< "$(sudo dislocker-find)"
            ;;

        "mounted_files")
            echo "Construindo string de alvos: Arquivos Montados"
            # Chama o script que já tem sudo interno
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
    # cp sem sudo para Desktop
    cp "$IPED_DIR/Ferramenta_de_Pesquisa.sh" "$OUTPUT_DIR/"
    cp "$IPED_DIR/$DESKTOP_FILE" "/home/kali/Desktop/IPED-Caso.desktop"

    # Define o proprietário como 'kali' (precisa de sudo apenas para o atalho)
    # OUTPUT_DIR já deve pertencer a kali devido à lógica em setup_output_dir
    sudo chown kali:kali "/home/kali/Desktop/IPED-Caso.desktop" || echo "Aviso: Falha ao mudar proprietário do atalho"

    # cd sem sudo
    cd "$OUTPUT_DIR"
    if [ -f "./Ferramenta_de_Pesquisa.sh" ]; then
        # Executa como kali (sem sudo)
        ./Ferramenta_de_Pesquisa.sh
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
        --profile) SELECTED_PROFILE="$2"; shift ;;
        --target) TARGET_MODE="$2"; shift ;;
        --path) MANUAL_PATH="$2"; shift ;;
        *) echo "Parâmetro desconhecido: $1"; exit 1 ;;
    esac
    shift
done
PROFILE=$SELECTED_PROFILE

echo "============================================="
echo "      INICIALIZANDO MOTOR IPED"
echo "============================================="
echo "Perfil selecionado inicialmente: $PROFILE"
echo "Alvo: $TARGET_MODE"
[ ! -z "$MANUAL_PATH" ] && echo "Caminho: $MANUAL_PATH"
echo "---------------------------------------------"


# 2. Setup
# cd sem sudo
cd "$IPED_DIR" || { echo "Erro: Diretório $IPED_DIR não encontrado."; exit 1; }
# mplayer pode precisar de sudo
sudo mplayer &> /dev/null # Bugfix

# 3. Preparação
setup_output_dir # Define $OUTPUT_DIR, $CONTINUE_PROCESSING e $PROFILE

if ! $CONTINUE_PROCESSING; then
     build_target_string # Define $TARGET_STRING
fi


# 4. Construção e Log do Comando
if $CONTINUE_PROCESSING; then
    # RECOVERED_CMD já contém 'sudo java...'
    FINAL_CMD=$RECOVERED_CMD
    echo "========================================================"
    echo "COMANDO PARA CONTINUAR (Perfil Original '$PROFILE'):"
    echo "$FINAL_CMD"
    echo "========================================================"
else
    # JAVA_CMD_BASE já contém 'sudo java...'
    FINAL_CMD="$JAVA_CMD_BASE -o $OUTPUT_DIR -profile $PROFILE $LOG_FILE_OPT $KEYWORD_FILE_OPT $TARGET_STRING"
    echo "========================================================"
    echo "COMANDO FINAL A SER EXECUTADO:"
    echo "$FINAL_CMD"
    echo "========================================================"

    # LOG DO COMANDO (sem sudo, pois o arquivo está no Desktop do kali)
    echo "Registrando comando em $COMMAND_LOG_FILE..."
    mkdir -p "$(dirname "$COMMAND_LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executando: $FINAL_CMD" >> "$COMMAND_LOG_FILE"
    # chown sem sudo, pois o arquivo é do kali
    chown kali:kali "$COMMAND_LOG_FILE" || echo "Aviso: Falha ao mudar proprietário do arquivo de log do comando."
fi

echo "Iniciando IPED... Isso pode levar muito tempo."

# 5. Execução (FINAL_CMD já contém sudo)
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