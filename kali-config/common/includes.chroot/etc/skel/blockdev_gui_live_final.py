#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Gerenciador de Dispositivos de Bloco para Ambientes Live (Kali/Outros)
#
# FUNÇÕES PRINCIPAIS:
# 1. Exclui o dispositivo de boot (/run/live/medium) da lista.
# 2. Lista discos externos com cores: VERMELHO (Escrita Livre/RW) e VERDE (Bloqueado/RO).
# 3. Antes de alterar a permissão, tenta desmontar todas as partições filhas.
# 4. Altera a permissão de escrita (blockdev) no disco pai E em todas as partições.
# 5. Atualiza dinamicamente o ícone e o nome do atalho na área de trabalho para refletir
#    o estado global de segurança.

import sys
import subprocess
import os
import json
import math # Importado para formatação de tamanho

from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QListWidget, QPushButton, QLabel, QMessageBox,
    QListWidgetItem
)
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QIcon

# --- CONSTANTES DE CONFIGURAÇÃO ---
ICON_DIR = "/home/kali/Pictures/"
DESKTOP_FILE_PATH = "/home/kali/Desktop/Disk_Shield.desktop"
ICON_GREEN = "disk_shield_green.svg"
ICON_RED = "disk_shield_red.svg"
# -----------------------------------

class BlockDeviceManager(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Gerenciador de Bloqueio de Bloco - MODO LIVE")
        self.setMinimumWidth(650) # Aumenta a largura mínima da janela
        self.boot_device = self.get_boot_device()
        self.setup_ui()
        self.load_devices()

    def setup_ui(self):
        main_layout = QVBoxLayout(self)

        # Exibe o dispositivo de boot (informativo)
        if self.boot_device:
            main_layout.addWidget(QLabel(f"Dispositivo de Boot (Excluído): /dev/{self.boot_device}"))
        else:
            main_layout.addWidget(QLabel("Não foi possível identificar o dispositivo de Boot em /run/live/medium."))

        # 1. Lista de Dispositivos
        main_layout.addWidget(QLabel("Dispositivos de Bloco Disponíveis (Verde: RO / Vermelho: RW):"))
        self.device_list = QListWidget()
        self.device_list.setSelectionMode(QListWidget.SelectionMode.SingleSelection)
        main_layout.addWidget(self.device_list)

        # 2. Botões de Ação
        button_layout = QHBoxLayout()
        
        self.refresh_button = QPushButton("Atualizar Lista")
        self.refresh_button.clicked.connect(self.load_devices)
        button_layout.addWidget(self.refresh_button)

        self.block_button = QPushButton("Bloquear Escrita (RO)")
        self.block_button.clicked.connect(lambda: self.set_write_protect(1))
        self.block_button.setEnabled(False) 
        button_layout.addWidget(self.block_button)

        self.unblock_button = QPushButton("Liberar Escrita (RW)")
        self.unblock_button.clicked.connect(lambda: self.set_write_protect(0))
        self.unblock_button.setEnabled(False) 
        button_layout.addWidget(self.unblock_button)
        
        main_layout.addLayout(button_layout)
        
        self.device_list.itemSelectionChanged.connect(self.update_buttons)
        
    def _format_size_bytes(self, size_bytes):
        """Converte tamanho em bytes para GB, TB, etc. (IEC units)"""
        if not size_bytes or size_bytes == 0:
            return "0 B"
        
        size = int(size_bytes)
        # Unidades: B, KiB, MiB, GiB, TiB
        units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
        # log2(1024) = 10
        i = int(math.floor(math.log(size, 1024)))
        
        # Garante que não ultrapasse o índice de unidades
        if i >= len(units):
            i = len(units) - 1
            
        p = math.pow(1024, i)
        s = round(size / p, 1)
        
        return f"{s} {units[i]}"


    def _update_desktop_icon(self, is_secure):
        """
        Atualiza o ícone e o nome no arquivo .desktop na área de trabalho usando 'sudo sed'.
        """
        icon_file = ICON_GREEN if is_secure else ICON_RED
        icon_path = ICON_DIR + icon_file
        
        # O nome do atalho indica a PRÓXIMA ação (ex: se está seguro, a próxima ação é Liberar).
        next_action_name = "Liberar Escrita" if is_secure else "Bloquear Escrita"
        
        try:
            # Comando 1: Atualiza o caminho do ícone
            subprocess.run(
                ["sudo", "sed", "-i", f"s|^Icon=.*|Icon={icon_path}|", DESKTOP_FILE_PATH],
                check=True, capture_output=True, text=True
            )
            # Comando 2: Atualiza o nome do atalho
            subprocess.run(
                ["sudo", "sed", "-i", f"s|^Name=.*|Name={next_action_name}|", DESKTOP_FILE_PATH],
                check=True, capture_output=True, text=True
            )
            
            # Comando 3: Chama o script externo para setar a confiança no desktop.
            subprocess.run(
                ["/bin/bash", "/etc/profile.d/trust_desktop_icons.sh"],
                check=True, capture_output=True, text=True
            )
 
            
        except subprocess.CalledProcessError as e:
            print(f"AVISO: Falha ao atualizar o arquivo .desktop ({e.stderr.strip()}). Verifique se o script foi executado com sudo e se o caminho está correto.")
            pass

    def get_boot_device(self):
        """Identifica o dispositivo de bloco raiz do boot Live em /run/live/medium."""
        try:
            # 1. Encontra a partição de origem montada em /run/live/medium
            result = subprocess.run(
                ["findmnt", "-n", "-o", "SOURCE", "/run/live/medium"],
                capture_output=True, text=True, check=True
            )
            source = result.stdout.strip()
            
            if not source:
                return None
            
            # 2. Se for uma partição, busca o dispositivo pai (PKNAME).
            result_parent = subprocess.run(
                ["lsblk", "-n", "-o", "PKNAME", source],
                capture_output=True, text=True, check=True
            )
            parent_name = result_parent.stdout.strip()

            if parent_name:
                return parent_name # Retorna o nome do pai (ex: sdb)
            
            # 3. Se não houver pai, retorna o nome do dispositivo (ex: sr0)
            return source.replace("/dev/", "")
            
        except subprocess.CalledProcessError:
            return None
        except Exception:
            return None
            
    def _get_ro_status(self, device_name):
        """
        Obtém o status real de Somente Leitura (1=RO, 0=RW) usando blockdev --getro.
        Requer sudo.
        """
        try:
            result = subprocess.run(
                ["sudo", "blockdev", "--getro", f"/dev/{device_name}"],
                capture_output=True, text=True, check=True
            )
            # blockdev --getro retorna 1 (RO) ou 0 (RW) na saída padrão
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            # Se o comando falhar (dispositivo inválido ou sem permissão), assume RW por segurança
            return "0" 
        except Exception:
            return "0"

    def update_buttons(self):
        """Habilita/desabilita os botões de acordo com a seleção."""
        is_selected = len(self.device_list.selectedItems()) > 0
        self.block_button.setEnabled(is_selected)
        self.unblock_button.setEnabled(is_selected)

    def get_block_devices(self):
        """
        Retorna detalhes dos dispositivos de bloco usando JSON,
        incluindo o rótulo (LABEL) da maior partição para identificação.
        O status RO é obtido diretamente do blockdev para consistência.
        """
        devices = []
        try:
            # Executa lsblk para obter a lista hierárquica completa em JSON
            # Pedimos o tamanho em BYTES (-b) para formatar corretamente.
            result = subprocess.run(
                ["lsblk", "-J", "-b", "-o", "NAME,SIZE,MODEL,LABEL,TYPE"],
                capture_output=True, text=True, check=True
            )
            data = json.loads(result.stdout)
            
            for disk in data.get('blockdevices', []):
                # Filtra apenas discos principais (type='disk') e exclui o de boot
                if disk.get('type') == 'disk' and disk.get('name') != self.boot_device:
                    
                    # *** Lógica para encontrar o rótulo da maior partição ***
                    max_partition_size = 0
                    partition_label = "N/A"
                    
                    for child in disk.get('children', []):
                        if child.get('type') == 'part':
                            # Tamanho em bytes
                            size_bytes = int(child.get('size', 0))
                            if size_bytes > max_partition_size:
                                max_partition_size = size_bytes
                                # Captura o rótulo, se disponível
                                label = child.get('label')
                                partition_label = f"[{label}]" if label else "Sem Rótulo"
                                
                    
                    # *** OBTÉM O STATUS RO REAL USANDO blockdev ***
                    ro_status = self._get_ro_status(disk.get('name'))
                    
                    # *** Formatação do Tamanho do Disco Principal ***
                    disk_size_display = self._format_size_bytes(disk.get('size'))
                    
                    devices.append({
                        "name": disk.get('name'),
                        "ro_status": ro_status,
                        "size": disk_size_display,
                        "model": disk.get('model', 'N/A'),
                        "partition_label": partition_label
                    })
        except Exception as e:
            QMessageBox.critical(self, "Erro de Listagem", f"Falha ao processar lista de dispositivos: {e}")
        return devices

    def load_devices(self):
        """Preenche a lista de dispositivos com status, cor e detalhes e atualiza o estado global."""
        self.device_list.clear()
        devices = self.get_block_devices()
        
        is_global_secure = True # Assume que está seguro (todos RO)

        for dev in devices:
            name = dev["name"]
            ro_status = dev["ro_status"]
            size = dev["size"]
            model = dev["model"]
            partition_label = dev["partition_label"]
            
            # 1. Determina o status e a cor (baseado na leitura REAL do blockdev)
            if ro_status == "1":
                status = "BLOQUEADO (Somente Leitura - RO)"
                color = QColor("green")
            else:
                status = "DESBLOQUEADO (Escrita Habilitada - RW)"
                color = QColor("red")
                is_global_secure = False # Se um estiver RW, o estado não é seguro
            
            # 2. Formata o texto para a lista (Mostra o rótulo da maior partição)
            item_text = (
                f"/dev/{name} | Status: {status}\n"
                f"   Tamanho: {size} | Partição: {partition_label} | Modelo: {model}"
            )
            item = QListWidgetItem(item_text)
            
            # 3. Aplica a cor do texto
            item.setForeground(color)
            
            # 4. Armazena o nome do dispositivo como dado do usuário
            item.setData(Qt.ItemDataRole.UserRole, name) 
            self.device_list.addItem(item)
            
        self.update_buttons()
        # Atualiza o ícone da aplicação e o atalho do desktop
        self.setWindowIcon(QIcon(ICON_DIR + (ICON_GREEN if is_global_secure else ICON_RED)))
        self._update_desktop_icon(is_global_secure)


    def _get_all_targets(self, device_name):
        """Retorna o dispositivo pai e todas as suas partições (filhas) usando lsblk."""
        try:
            # -n: sem cabeçalhos, -r: formato raw, -o NAME: apenas nome
            result = subprocess.run(
                ["lsblk", "-n", "-r", "-o", "NAME", f"/dev/{device_name}"],
                capture_output=True, text=True, check=True
            )
            # Retorna uma lista de nomes de dispositivos (ex: ['sdb', 'sdb1', 'sdb2'])
            return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        except Exception:
            return [device_name] # Retorna apenas o nome se falhar

    def _unmount_target(self, target_name):
        """Tenta desmontar um dispositivo ou partição."""
        try:
            # umount -f tenta forçar a desmontagem
            subprocess.run(
                ["sudo", "umount", "-f", f"/dev/{target_name}"],
                capture_output=True, text=True, check=True
            )
            return f"Sucesso: /dev/{target_name} desmontado."
        except subprocess.CalledProcessError as e:
            # O código de erro 32 significa que o dispositivo não estava montado, o que é OK.
            if "not mounted" in e.stderr or e.returncode == 32:
                 return f"Ignorado: /dev/{target_name} não estava montado."
            return f"Falha ao desmontar /dev/{target_name}: {e.stderr.strip()}"
        except Exception as e:
            return f"Erro ao desmontar /dev/{target_name}: {e}"

    def set_write_protect(self, ro_state):
        """Executa a desmontagem e o comando blockdev em todos os alvos (pai e partições)."""
        selected_items = self.device_list.selectedItems()
        if not selected_items:
            return

        device_name = selected_items[0].data(Qt.ItemDataRole.UserRole)
        command_arg = "--setro" if ro_state == 1 else "--setrw"
        
        action = "Bloquear Escrita (RO)" if ro_state == 1 else "Liberar Escrita (RW)"
        
        reply = QMessageBox.question(self, action, 
            f"Confirmação: Você deseja {action.lower()} no dispositivo /dev/{device_name} e em todas as suas partições?",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No, 
            QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.No:
            return

        targets = self._get_all_targets(device_name)
        log_messages = []

        # Etapa 1: Desmontar todos os alvos
        log_messages.append("\n--- Tentativa de Desmontagem ---")
        for target in targets:
            log_messages.append(self._unmount_target(target))

        # Etapa 2: Aplicar o comando blockdev em todos os alvos
        log_messages.append("\n--- Aplicação de Permissão ---")
        success_count = 0
        for target in targets:
            full_command = ["sudo", "blockdev", command_arg, f"/dev/{target}"]
            try:
                subprocess.run(
                    full_command,
                    capture_output=True, text=True, check=True
                )
                log_messages.append(f"Sucesso: /dev/{target} definido como {action}.")
                success_count += 1
            except subprocess.CalledProcessError as e:
                log_messages.append(f"Falha em /dev/{target}: {e.stderr.strip()}")
            except Exception as e:
                log_messages.append(f"Erro inesperado em /dev/{target}: {e}")

        # Exibir resultado final
        if success_count > 0:
            QMessageBox.information(self, "Operação Concluída", 
                f"{action} concluído em {success_count}/{len(targets)} alvos.\n\nDetalhes:\n" + "\n".join(log_messages)
            )
        else:
            QMessageBox.critical(self, "Falha na Operação", 
                f"Nenhum alvo foi alterado com sucesso.\n\nDetalhes:\n" + "\n".join(log_messages)
            )
            
        self.load_devices() # Recarrega para mostrar o novo status, cor, e estado global

if __name__ == "__main__":
    # Verifica as dependências
    missing_commands = []
    for cmd in ["lsblk", "findmnt", "blockdev"]:
        if not (os.path.exists(f"/usr/bin/{cmd}") or os.path.exists(f"/bin/{cmd}") or os.path.exists(f"/sbin/{cmd}")):
            missing_commands.append(cmd)
        
    if missing_commands:
        print(f"Erro: Os comandos {', '.join(missing_commands)} não foram encontrados.")
        print("Certifique-se de que o pacote 'util-linux' esteja instalado.")
        sys.exit(1)
        
    app = QApplication(sys.argv)
    manager = BlockDeviceManager()
    manager.show()
    sys.exit(app.exec())
