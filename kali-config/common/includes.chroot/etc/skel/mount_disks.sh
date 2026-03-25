#!/bin/bash

# -----------------------------------------------------------------------------
# Script Forense de Montagem Automática (Somente Leitura)
#
# Propósito: Montar todos os dispositivos de bloco detectados (exceto o
#            sistema Live USB) em modo somente leitura para análise forense.
#
# Funcionalidades:
# - Monta partições, discos sem partição (superfloppy), LDM e BitLocker.
# - Garante que todas as montagens sejam SOMENTE LEITURA.
# - Impede a execução, acesso a dispositivos e SUID (noexec, nodev, nosuid).
# - Impede a reprodução do journal (noload para ext4, ro para ntfs).
# - Usa o driver 'ntfs' para todas as partições NTFS.
# - Verifica se um dispositivo já está montado.
# - Ignora o disco do sistema Live (USB, CD/DVD, etc.).
# - Gera um relatório final com o Zenity (pode ser desabilitado)
#   que inclui SUCESSOS e ERROS e desaparece após 10s.
#
# Uso:
#   sudo ./mount_disks.sh
#   sudo ./mount_disks.sh --no-report (para desabilitar o relatório Zenity)
# -----------------------------------------------------------------------------

source /home/kali/forensic_utils.sh

MEDIA_DIR="/run/media"

# --- Configuração Inicial ---

SHOW_REPORT=true
if [[ "$1" == "--no-report" ]]; then
  SHOW_REPORT=false
  echo "Relatório Zenity no final foi desabilitado via parâmetro."
fi

# Arquivo de log temporário para o relatório final
MOUNT_LOG=$(mktemp)
# Garante que o log seja limpo ao sair
trap 'rm -f "$MOUNT_LOG"' EXIT

# --- Pre-cache de Dispositivos BitLocker ---
echo "Verificando dispositivos BitLocker antecipadamente..."
# Armazena a lista de dispositivos BDE para evitar montagem na Seção 1
BITLOCKER_DEVICES=$(sudo dislocker-find)

# Cria o diretório base para o dislocker (apenas uma vez)
sudo mkdir -p /dislocker

# --- Detecção Robusta do Sistema Live ---

echo "Identificando o disco do sistema Live para excluí-lo..."
ROOT_DISK_NAME=$(get_boot_disk_name)

if [[ -n "$ROOT_DISK_NAME" ]]; then
    echo "Disco do sistema Live identificado: $ROOT_DISK_NAME. Este disco será ignorado."
else
    echo "Aviso: Falha ao determinar disco de boot."
    ROOT_DISK_NAME="null_failsafe"
fi

# --- Função Auxiliar de Montagem Forense ---

mount_forensic() {
    local device_path="$1"
    local mount_point="$2"
    local device_name
    device_name=$(basename "$device_path")

    # 1. Ignorar o disco do sistema Live
    if [[ -n "$ROOT_DISK_NAME" && "$device_name" == *"$ROOT_DISK_NAME"* ]]; then
        return
    fi

    # 2. Verificar se já está montado
    if findmnt --mountpoint "$mount_point" &> /dev/null; then
        echo "$device_path já está montado em $mount_point. Ignorando."
        return
    fi

    # 3. VERIFICAÇÃO DE BITLOCKER (MELHORIA)
    # Verifica se o dispositivo está na lista BDE. Se estiver, pula,
    # pois será tratado pela Seção 3.
    if echo "$BITLOCKER_DEVICES" | grep -q "^$device_path$"; then
        echo "Ignorando $device_path (detectado BitLocker, será tratado na Seção 3)."
        return
    fi

    # 4. Detectar tipo de sistema de arquivos
    local fs_type_output
    fs_type_output=$(lsblk -no FSTYPE "$device_path")
    
    local line_count
    line_count=$(echo "$fs_type_output" | wc -l)

    if [[ $line_count -gt 1 ]]; then
        echo "Ignorando $device_path (dispositivo contêiner com partições)."
        return
    fi
    
    local fs_type="$fs_type_output"

    if [[ -z "$fs_type" ]]; then
        echo "Ignorando $device_path (sem sistema de arquivos detectável)."
        return
    fi
    
    # Opções de base, cruciais para segurança e forense
    local mount_options="ro,noexec,nodev,nosuid"
    local type_options="" # Opções de tipo de FS, ex: -t ntfs

    # 5. Adicionar opções específicas de journal e tipo
    if [[ "$fs_type" == "ntfs" ]]; then
        type_options="-t ntfs"
        
    elif [[ "$fs_type" == "ext3" || "$fs_type" == "ext4" ]]; then
        mount_options="$mount_options,noload"
        
    elif [[ "$fs_type" == "xfs" || "$fs_type" == "jfs" ]]; then
        mount_options="$mount_options,norecovery"
    fi

    # 6. Criar ponto de montagem e montar
    echo "Tentando montar $device_path (Tipo: $fs_type) em $mount_point..."
    sudo mkdir -p "$mount_point"
    
    if sudo mount -o "$mount_options" $type_options "$device_path" "$mount_point"; then
        echo "Sucesso: $device_path montado em $mount_point"
        echo "SUCESSO: $device_path -> $mount_point (Tipo: ${fs_type:-desconhecido}, Opções: $mount_options)" >> "$MOUNT_LOG"
    else
        echo "Erro: Falha ao montar $device_path em $mount_point."
        echo "ERRO: Falha ao montar $device_path em $mount_point." >> "$MOUNT_LOG"
        sudo rmdir "$mount_point" &> /dev/null
    fi
}

# --- 1. Montagem de Partições Padrão ---

echo "Montando partições padrão (somente leitura)..."
while read -r line; do
    disk_name=$(echo "$line" | awk '{print $1}') # e.g., sda, sda1, sdb, sr0
    if [[ -n "$disk_name" ]]; then
        mount_forensic "/dev/$disk_name" "$MEDIA_DIR/$disk_name"
    fi
done <<< "$(lsblk -lno NAME,TYPE | grep -E 'part|disk|rom')"


# --- 2. Montagem de LDM (RAID do Windows) ---

echo "Tentando montar volumes LDM (RAID do Windows)..."
sudo ldmtool create all > /dev/null 2>&1
sleep 2 

while read -r line; do
    ldm_name=$(echo "$line" | awk '{print $1}') # e.g., ldm_vol_...
    if [[ -n "$ldm_name" ]]; then
        mount_forensic "/dev/mapper/$ldm_name" "$MEDIA_DIR/$ldm_name"
    fi
done <<< "$(lsblk -lno NAME,TYPE | grep 'dm')"


# --- 3. Montagem de Partições BitLocker ---

echo "Verificando partições BitLocker (da lista pré-carregada)..."
# MELHORIA: Itera sobre a variável $BITLOCKER_DEVICES em vez de chamar dislocker-find novamente
while read -r bde_device_path; do
    if [[ -n "$bde_device_path" ]]; then
        
        # CORREÇÃO: Removido 'local' das declarações de variáveis
        disk_name=$(basename "$bde_device_path") 
        decrypted_mount_point="$MEDIA_DIR/decrypted_$disk_name"
        dislocker_path="/dislocker/bitlocker_$disk_name"
        dislocker_file="$dislocker_path/dislocker-file"
        bde_mount_options="loop,ro,noexec,nodev,nosuid"

        if [[ -n "$ROOT_DISK_NAME" && "$disk_name" == *"$ROOT_DISK_NAME"* ]]; then
            echo "Ignorando BitLocker em $bde_device_path (parte do sistema Live)."
            continue
        fi

        if findmnt --mountpoint "$decrypted_mount_point" &> /dev/null; then
            echo "BitLocker de $bde_device_path já está montado em $decrypted_mount_point. Ignorando."
            continue
        fi

        echo "Detectada partição BitLocker em $bde_device_path"
        sudo mkdir -p "$dislocker_path"
        sudo mkdir -p "$decrypted_mount_point"
        
        sudo dislocker -V "$bde_device_path" -- "$dislocker_path" -r

        if sudo test -f "$dislocker_file"; then
            # Sucesso (suspenso)
            echo "BitLocker em $bde_device_path está suspenso. Montando..."
            if sudo mount -o $bde_mount_options "$dislocker_file" "$decrypted_mount_point" -t ntfs; then
                echo "Sucesso: BitLocker de $bde_device_path montado em $decrypted_mount_point"
                echo "SUCESSO: $bde_device_path (BitLocker) -> $decrypted_mount_point (Tipo: ntfs, Opções: $bde_mount_options)" >> "$MOUNT_LOG"
            else
                echo "Erro: Falha ao montar o arquivo dislocker-file de $bde_device_path."
                echo "ERRO: Falha ao montar o arquivo dislocker-file de $bde_device_path (suspenso)." >> "$MOUNT_LOG"
                sudo rmdir "$decrypted_mount_point" "$dislocker_path" &> /dev/null
            fi
        else
            # 4. Precisa de chave
            echo "BitLocker em $bde_device_path requer uma chave."
            
            while true; do
                BITLOCKER_INFO=('', '')
                previousline=""
                while read -r line ; do
                    if [[ ! -z $line ]]; then
                        if [[ $line =~ "Description:" ]]; then BITLOCKER_INFO[0]=$line; fi 
                        if [[ $line =~ "VMK protected with recovery passphrase" ]]; then BITLOCKER_INFO[1]=${previousline^^}; fi
                        previousline=$line;
                    fi
                done <<< "$(sudo cryptsetup bitlkDump "$bde_device_path")"

                bitlocker_pass=$(zenity --entry --title="Detectado BitLocker!" --text="Detectou-se uma particao criptografada com bitlocker em $bde_device_path, porem nao foi possivel decripta-la automaticamente. \nEste script tentara montar as demais particoes. \nCaso se tenha a chave de recuperacao ou a senha de acesso digite-a abaixo: \n${BITLOCKER_INFO[0]} \n${BITLOCKER_INFO[1]}" --entry-text "ChaveDeRecuperacao" --width=500)
                
                if [ $? = 0 ]; then
                    # Tenta com Chave de Recuperação
                    sudo dislocker -V "$bde_device_path" -p"$bitlocker_pass" -- "$dislocker_path" -r
                    if sudo test -f "$dislocker_file"; then
                        echo "Chave de recuperação aceita. Montando..."
                        if sudo mount -o $bde_mount_options "$dislocker_file" "$decrypted_mount_point" -t ntfs; then
                            echo "Sucesso: BitLocker de $bde_device_path montado em $decrypted_mount_point"
                            echo "SUCESSO: $bde_device_path (BitLocker) -> $decrypted_mount_point (Tipo: ntfs, Opções: $bde_mount_options)" >> "$MOUNT_LOG"
                        else
                            echo "Erro: Falha ao montar o arquivo dislocker-file de $bde_device_path."
                            echo "ERRO: Falha ao montar o arquivo dislocker-file de $bde_device_path (com Chave)." >> "$MOUNT_LOG"
                        fi
                        break
                    else
                        # Tenta com Senha de Usuário
                        sudo dislocker -V "$bde_device_path" --user-password="$bitlocker_pass" -- "$dislocker_path" -r
                        if sudo test -f "$dislocker_file"; then
                            echo "Senha de usuário aceita. Montando..."
                            if sudo mount -o $bde_mount_options "$dislocker_file" "$decrypted_mount_point" -t ntfs; then
                                echo "Sucesso: BitLocker de $bde_device_path montado em $decrypted_mount_point"
                                echo "SUCESSO: $bde_device_path (BitLocker) -> $decrypted_mount_point (Tipo: ntfs, Opções: $bde_mount_options)" >> "$MOUNT_LOG"
                            else
                                echo "Erro: Falha ao montar o arquivo dislocker-file de $bde_device_path."
                                echo "ERRO: Falha ao montar o arquivo dislocker-file de $bde_device_path (com Senha)." >> "$MOUNT_LOG"
                            fi
                            break
                        else
                            zenity --error --title="Erro de Chave BitLocker!" --text="A chave ou senha fornecida nao decifrou a unidade." --width=300 --timeout=20
                            echo "ERRO: Chave/Senha inválida fornecida para $bde_device_path." >> "$MOUNT_LOG"
                        fi
                    fi
                else
                    echo "Montagem do BitLocker em $bde_device_path cancelada pelo usuário."
                    echo "AVISO: Montagem do BitLocker em $bde_device_path cancelada pelo usuário." >> "$MOUNT_LOG"
                    sudo rmdir "$decrypted_mount_point" "$dislocker_path" &> /dev/null
                    break
                fi
            done
        fi
    fi
done <<< "$BITLOCKER_DEVICES" # MELHORIA: Usa a variável pré-carregada


# --- 4. Relatório Final ---

echo "Processo de montagem concluído."

if [ "$SHOW_REPORT" = true ]; then
    REPORT_CONTENT=$(cat "$MOUNT_LOG")
    if [ -z "$REPORT_CONTENT" ]; then
        zenity --info --title="Relatório de Montagem" --text="Nenhuma atividade de montagem (sucesso ou erro) foi registrada." --width=400 --timeout=10
    else
        echo -e "Relatório de Montagem (Modo Forense Seguro):\n\n$REPORT_CONTENT" | zenity --text-info --title="Relatório de Montagem Forense" --width=700 --height=400 --font="Monospace" --timeout=10
    fi
else
    echo "Relatório Zenity desabilitado. Saída do console:"
    if [ -s "$MOUNT_LOG" ]; then
        cat "$MOUNT_LOG"
    else
        echo "Nenhuma atividade de montagem (sucesso ou erro) foi registrada."
    fi
fi

# A limpeza do $MOUNT_LOG é tratada pelo 'trap' no início.
