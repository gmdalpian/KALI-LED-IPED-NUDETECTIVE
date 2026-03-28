#!/bin/bash

LOG_FILE="/var/log/nvidia-select.log"
KERNEL=$(uname -r)

# --- Função de Logging Avançada (Grava no arquivo e no dmesg) ---
log() {
    local MSG="[NVIDIA-BOOT] $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $MSG" >> "$LOG_FILE"
    echo "$MSG" > /dev/kmsg
}

log "===== INICIANDO SELEÇÃO DINÂMICA DE DRIVER NVIDIA ====="

# 1. Verificações Iniciais (Modo Seguro)
if grep -q "nonvidia" /proc/cmdline; then
    log "Aviso: Parâmetro 'nonvidia' detectado no boot. Abortando carregamento."
    exit 0
fi

if [ ! -x /usr/local/bin/gpu-detect.sh ]; then
    log "ERRO CRÍTICO: /usr/local/bin/gpu-detect.sh não encontrado ou sem permissão de execução."
    exit 1
fi

eval $(/usr/local/bin/gpu-detect.sh)
log "Hardware detectado - Vendor: $VENDOR | Arquitetura: $ARCH | Driver alvo: $DRIVER"

if [ "$VENDOR" != "NVIDIA" ]; then
    log "Nenhuma GPU NVIDIA prioritária. Saindo graciosamente."
    exit 0
fi

# 2. Preparar diretórios base para o OverlayFS
log "Criando diretórios de trabalho (work/upper) para OverlayFS em /run/ovl..."
mkdir -p /run/ovl/{bin_work,bin_upper,xdrv_work,xdrv_upper,xext_work,xext_upper} || log "Aviso: Falha ao criar diretórios base do OverlayFS."

# 3. Função Principal de Projeção Virtual
apply_nvidia_dynamic() {
    local TYPE=$1
    local SOURCE="/opt/nvidia/$TYPE/system_root"

    log "--------------------------------------------------------"
    log "Tentando aplicar ambiente virtual isolado: $TYPE"

    if [ ! -d "$SOURCE" ]; then
        log "ERRO: Diretório fonte $SOURCE não existe."
        return 1
    fi

    # A. Módulos do Kernel (Bind Mount)
    log "[Etapa 1/5] Montando módulos do kernel..."
    mount --bind "$SOURCE/lib/modules/$KERNEL/kernel/drivers/video" /lib/modules/$KERNEL/kernel/drivers/video || { log "ERRO: Bind mount dos módulos falhou."; return 1; }
    depmod -a || log "Aviso: Comando 'depmod -a' retornou erro."

    # B. Firmware GSP (OverlayFS)
    log "[Etapa 2/5] Projetando firmware da GPU..."
    if [ -d "$SOURCE/lib/firmware/nvidia" ]; then
        mkdir -p /lib/firmware/nvidia
        mount -t overlay overlay -o lowerdir="$SOURCE/lib/firmware/nvidia:/lib/firmware/nvidia" /lib/firmware/nvidia 2>/dev/null || \
        mount --bind "$SOURCE/lib/firmware/nvidia" /lib/firmware/nvidia || log "Aviso: Falha no mount do firmware."
    fi

    # C. Bibliotecas (ldconfig nativo)
    log "[Etapa 3/5] Configurando cache de bibliotecas (ldconfig)..."
    mkdir -p /etc/ld.so.conf.d
    if [ -d "$SOURCE/usr/lib/x86_64-linux-gnu" ]; then
        echo "$SOURCE/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/99-nvidia.conf
        ldconfig || log "Aviso: ldconfig falhou."
    else
        log "ERRO: Bibliotecas em $SOURCE/usr/lib/ ausentes."
        return 1
    fi

    # D. Binários e Módulos Xorg (OverlayFS)
    log "[Etapa 4/5] Aplicando OverlayFS em /usr/bin e diretórios do X11..."
    mount -t overlay overlay -o lowerdir="$SOURCE/usr/bin:/usr/bin",upperdir=/run/ovl/bin_upper,workdir=/run/ovl/bin_work /usr/bin || return 1

    mkdir -p /usr/lib/xorg/modules/drivers
    mkdir -p /usr/lib/xorg/modules/extensions
    
    if [ -d "$SOURCE/usr/lib/xorg/modules/drivers" ]; then
        mount -t overlay overlay -o lowerdir="$SOURCE/usr/lib/xorg/modules/drivers:/usr/lib/xorg/modules/drivers",upperdir=/run/ovl/xdrv_upper,workdir=/run/ovl/xdrv_work /usr/lib/xorg/modules/drivers
    fi
    if [ -d "$SOURCE/usr/lib/xorg/modules/extensions" ]; then
        mount -t overlay overlay -o lowerdir="$SOURCE/usr/lib/xorg/modules/extensions:/usr/lib/xorg/modules/extensions",upperdir=/run/ovl/xext_upper,workdir=/run/ovl/xext_work /usr/lib/xorg/modules/extensions
    fi

    # E. Configuração Dinâmica do X11 (Força o uso do driver NVIDIA)
    log "[Etapa 5/5] Forçando xorg.conf dinâmico para liberar resolução da tela..."
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/20-nvidia.conf <<EOF
Section "Device"
    Identifier "Nvidia Card"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"
EndSection
EOF

    # 4. Carregamento e Validação (Com log detalhado)
    log ">>> Iniciando ativação do módulo NVIDIA no Kernel..."
    if modprobe -v nvidia >> "$LOG_FILE" 2>&1; then
        log "Módulo 'nvidia' base carregado. Subindo nvidia_drm (KMS) para interface gráfica..."
        timeout 10 modprobe -v nvidia_drm modeset=1 >> "$LOG_FILE" 2>&1 || log "Aviso: Falha no nvidia_drm."
        
        log "Efetuando ping na GPU via nvidia-smi para validar CUDA/Userspace..."
        if nvidia-smi >> "$LOG_FILE" 2>&1; then
            log "SUCESSO ABSOLUTO: Driver $TYPE validado. Interface gráfica e CUDA prontos para uso."
            return 0
        else
            log "FALHA CRÍTICA: Módulo carregou, mas nvidia-smi falhou."
            log "--- DUMP DE DIAGNÓSTICO ---"
            lsmod | grep nvidia >> "$LOG_FILE"
            dmesg | tail -n 25 >> "$LOG_FILE"
            log "--- FIM DO DUMP ---"
        fi
    else
        log "ERRO FATAL: modprobe nvidia falhou."
        dmesg | tail -n 15 >> "$LOG_FILE"
    fi
    
    # 5. Rollback preventivo em caso de falha
    log "Iniciando rollback de configurações ($TYPE) para tentar o próximo candidato..."
    rm -f /etc/ld.so.conf.d/99-nvidia.conf
    rm -f /etc/X11/xorg.conf.d/20-nvidia.conf
    ldconfig
    
    umount /usr/bin 2>/dev/null || true
    umount /lib/modules/$KERNEL/kernel/drivers/video 2>/dev/null || true
    return 1
}

# 6. Lógica de Tentativa Dinâmica
[[ "$DRIVER" == "open" ]] && ORDER=("open" "legacy") || ORDER=("legacy" "open")

log "A arquitetura da GPU solicita a ordem de tentativa: ${ORDER[*]}"

for T in "${ORDER[@]}"; do
    apply_nvidia_dynamic "$T" && exit 0
done

log "FALHA GERAL: Esgotadas as opções de drivers NVIDIA. O sistema continuará com os drivers de vídeo genéricos/Nouveau."
exit 1