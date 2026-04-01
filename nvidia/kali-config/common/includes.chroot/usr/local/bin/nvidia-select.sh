#!/bin/bash

LOG_FILE="/var/log/nvidia-select.log"
KERNEL=$(uname -r)

# --- Função de Logging Avançada ---
log() {
    local MSG="[NVIDIA-BOOT] $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $MSG" >> "$LOG_FILE"
    echo "$MSG" > /dev/kmsg
}

log "===== INICIANDO CARREGAMENTO DO DRIVER NVIDIA ====="

# 1. Verificações Iniciais
if grep -q "nonvidia" /proc/cmdline; then
    log "Aviso: Parâmetro 'nonvidia' detectado no boot. Abortando carregamento."
    exit 0
fi

if [ ! -x /usr/local/bin/gpu-detect.sh ]; then
    log "ERRO CRÍTICO: /usr/local/bin/gpu-detect.sh não encontrado."
    exit 1
fi

eval $(/usr/local/bin/gpu-detect.sh)
log "Hardware detectado - Vendor: $VENDOR | Arquitetura: $ARCH | Driver alvo: $DRIVER"

if [ "$VENDOR" != "NVIDIA" ]; then
    log "Nenhuma GPU NVIDIA prioritária. Saindo graciosamente."
    exit 0
fi

# 2. Definição do Alvo Único
TYPE="$DRIVER"
SOURCE="/opt/nvidia/$TYPE/system_root"

log "--------------------------------------------------------"
log "Aplicando ambiente virtual isolado para o driver: $TYPE"

if [ ! -d "$SOURCE" ]; then
    log "ERRO FATAL: Diretório fonte $SOURCE não existe."
    exit 1
fi

log "Criando diretórios de trabalho (work/upper) para OverlayFS..."
mkdir -p /run/ovl/{bin_work,bin_upper,xdrv_work,xdrv_upper,xext_work,xext_upper}

# A. Firmware GSP (AGORA É A ETAPA 1 - Prepara o terreno)
log "[Etapa 1/6] Projetando firmware da GPU..."
if [ -d "$SOURCE/usr/lib/firmware/nvidia" ]; then
    mkdir -p /usr/lib/firmware/nvidia
    mount -t overlay overlay -o lowerdir="$SOURCE/usr/lib/firmware/nvidia:/usr/lib/firmware/nvidia" /usr/lib/firmware/nvidia 2>/dev/null || \
    mount --bind "$SOURCE/usr/lib/firmware/nvidia" /usr/lib/firmware/nvidia
fi

# B. OpenCL e Vulkan
log "[Etapa 2/6] Configurando registros OpenCL/Vulkan..."
if [ -d "$SOURCE/etc/OpenCL" ]; then cp -a "$SOURCE/etc/OpenCL/." /etc/OpenCL/ 2>/dev/null || true; fi
if [ -d "$SOURCE/etc/vulkan" ]; then cp -a "$SOURCE/etc/vulkan/." /etc/vulkan/ 2>/dev/null || true; fi

# C. Bibliotecas (ldconfig nativo)
log "[Etapa 3/6] Configurando cache de bibliotecas (ldconfig)..."
mkdir -p /etc/ld.so.conf.d
if [ -d "$SOURCE/usr/lib/x86_64-linux-gnu" ]; then
    echo "$SOURCE/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/99-nvidia.conf
    ldconfig
else
    log "ERRO FATAL: Bibliotecas ausentes em $SOURCE/usr/lib/x86_64-linux-gnu"
    exit 1
fi

# D. Binários e Módulos Xorg
log "[Etapa 4/6] Aplicando OverlayFS em /usr/bin e diretórios do X11..."
mount -t overlay overlay -o lowerdir="$SOURCE/usr/bin:/usr/bin",upperdir=/run/ovl/bin_upper,workdir=/run/ovl/bin_work /usr/bin || exit 1

mkdir -p /usr/lib/xorg/modules/drivers
mkdir -p /usr/lib/xorg/modules/extensions

if [ -d "$SOURCE/usr/lib/xorg/modules/drivers" ]; then
    mount -t overlay overlay -o lowerdir="$SOURCE/usr/lib/xorg/modules/drivers:/usr/lib/xorg/modules/drivers",upperdir=/run/ovl/xdrv_upper,workdir=/run/ovl/xdrv_work /usr/lib/xorg/modules/drivers
fi
if [ -d "$SOURCE/usr/lib/xorg/modules/extensions" ]; then
    mount -t overlay overlay -o lowerdir="$SOURCE/usr/lib/xorg/modules/extensions:/usr/lib/xorg/modules/extensions",upperdir=/run/ovl/xext_upper,workdir=/run/ovl/xext_work /usr/lib/xorg/modules/extensions
fi

# E. Configuração Dinâmica do X11
log "[Etapa 5/6] Forçando xorg.conf dinâmico para interface gráfica..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/20-nvidia.conf <<EOF
Section "Device"
    Identifier "Nvidia Card"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"
EndSection
EOF

# F. Módulos do Kernel (MOVIDO PARA O FINAL - Só expõe quando tudo estiver pronto)
log "[Etapa 6/6] Montando módulos do kernel e atualizando depmod..."
mount --bind "$SOURCE/usr/lib/modules/$KERNEL/kernel/drivers/video" /usr/lib/modules/$KERNEL/kernel/drivers/video || { log "ERRO: Bind mount dos módulos falhou."; exit 1; }
depmod -a || true

# 4. Carregamento e Validação
log ">>> Iniciando ativação dos módulos NVIDIA no Kernel..."

# Mesmo que o udev já tenha tentado carregar no background durante o depmod, 
# rodar modprobe novamente é seguro e garante as dependências (drm, uvm).
if modprobe -v nvidia >> "$LOG_FILE" 2>&1; then
    log "Módulo 'nvidia' base carregado. Subindo dependências (DRM e UVM)..."
    
    timeout 10 modprobe -v nvidia_drm modeset=1 >> "$LOG_FILE" 2>&1 || true
    modprobe -v nvidia-uvm >> "$LOG_FILE" 2>&1 || true
    
    log "Aguardando udev criar os device nodes (necessário para o GSP)..."
    udevadm settle timeout=5 || true
    
    log "Validando via nvidia-smi (Aguardando boot do GSP que pode levar até 15s)..."
    SMI_OK=0
    for i in {1..15}; do
        if nvidia-smi >> "$LOG_FILE" 2>&1; then
            SMI_OK=1
            break
        fi
        sleep 1
    done

    if [ "$SMI_OK" -eq 1 ]; then
        log "SUCESSO ABSOLUTO: Driver $TYPE validado. Interface gráfica, CUDA e UVM prontos."
        exit 0
    else
        log "FALHA CRÍTICA: Módulos carregaram, mas nvidia-smi falhou após 15 segundos."
        dmesg | tail -n 25 >> "$LOG_FILE"
        exit 1
    fi
else
    log "ERRO FATAL: modprobe nvidia falhou."
    dmesg | tail -n 15 >> "$LOG_FILE"
    exit 1
fi