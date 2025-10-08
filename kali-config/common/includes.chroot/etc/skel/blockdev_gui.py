#!/usr/bin/env python3
import sys
import subprocess
import os

from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QListWidget, QPushButton, QLabel, QMessageBox,
    QListWidgetItem
)
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor

class BlockDeviceManager(QWidget):
    def __init__(self):
        super().__init__()
        # Determina o dispositivo de boot antes de montar a UI
        self.boot_device = self.get_boot_device()
        self.setWindowTitle("Gerenciador de Bloqueio de Bloco - MODO LIVE")
        self.setup_ui()
        self.load_devices()

    def setup_ui(self):
        main_layout = QVBoxLayout(self)

        # Exibe o dispositivo de boot (informativo)
        if self.boot_device:
            main_layout.addWidget(QLabel(f"Dispositivo de Boot (Excluído): /dev/{self.boot_device}"))
        else:
            main_layout.addWidget(QLabel("Não foi possível identificar o dispositivo de Boot (/run/live/medium)."))

        # 1. Lista de Dispositivos
        main_layout.addWidget(QLabel("Dispositivos de Bloco Externos (Verde: RO / Vermelho: RW):"))
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

        self.unblock_button = QPushButton("Desbloquear Escrita (RW)")
        self.unblock_button.clicked.connect(lambda: self.set_write_protect(0))
        self.unblock_button.setEnabled(False) 
        button_layout.addWidget(self.unblock_button)
        
        main_layout.addLayout(button_layout)
        
        self.device_list.itemSelectionChanged.connect(self.update_buttons)

    def get_boot_device(self):
        """
        Identifica o nome do dispositivo de bloco raiz do boot Live em /run/live/medium.
        Lida com partições (sdb1 -> sdb) e dispositivos sem partição (sr0 -> sr0).
        """
        try:
            # 1. Encontra a fonte (SOURCE) montada em /run/live/medium
            result = subprocess.run(
                ["findmnt", "-n", "-o", "SOURCE", "/run/live/medium"],
                capture_output=True, text=True, check=True, timeout=3
            )
            source_path = result.stdout.strip() # Ex: /dev/sdb1 ou /dev/sr0
            
            if not source_path or not source_path.startswith("/dev/"):
                return None
            
            # 2. Tenta encontrar o DISCO PAI (PKNAME) para partições
            # lsblk -n -o PKNAME /dev/sdb1 retorna 'sdb'
            # lsblk -n -o PKNAME /dev/sr0 retorna '' (vazio)
            result_parent = subprocess.run(
                ["lsblk", "-n", "-o", "PKNAME", source_path],
                capture_output=True, text=True, check=True, timeout=3
            )
            parent_name = result_parent.stdout.strip() 

            if parent_name:
                # É uma partição, retorna o nome do disco pai (ex: sdb)
                return parent_name
            else:
                # É o próprio dispositivo (ex: sr0 ou disco USB sem partição)
                # Extrai o nome do dispositivo (ex: sr0 de /dev/sr0)
                return os.path.basename(source_path)
            
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            # Se o findmnt falhar ou expirar (como em ambientes não Live)
            return None
        except Exception:
            return None

    def update_buttons(self):
        """Habilita/desabilita os botões de acordo com a seleção."""
        is_selected = len(self.device_list.selectedItems()) > 0
        self.block_button.setEnabled(is_selected)
        self.unblock_button.setEnabled(is_selected)

    def get_block_devices(self):
        """Retorna detalhes dos dispositivos de bloco, excluindo o de boot."""
        devices = []
        try:
            # Comando lsblk com colunas para: NOME, SOMENTE LEITURA, TAMANHO, MODELO/ID
            # A flag -d lista apenas os dispositivos raiz (sdX, sr0, etc.)
            result = subprocess.run(
                ["lsblk", "-d", "-n", "-o", "NAME,RO,SIZE,MODEL"],
                capture_output=True, text=True, check=True
            )
            
            for line in result.stdout.strip().split('\n'):
                parts = line.split()
                if len(parts) >= 3 and not parts[0].startswith("loop"):
                    name = parts[0]
                    
                    # *** FILTRO DE EXCLUSÃO DO DISPOSITIVO DE BOOT ***
                    if name == self.boot_device:
                        continue 

                    ro_status = parts[1]
                    size = parts[2]
                    model = " ".join(parts[3:]) if len(parts) > 3 else "N/A"
                    
                    devices.append({
                        "name": name,
                        "ro_status": ro_status,
                        "size": size,
                        "model": model.strip()
                    })
        except Exception as e:
            QMessageBox.critical(self, "Erro", f"Erro ao listar dispositivos: {e}")
        return devices

    def load_devices(self):
        """Preenche a lista de dispositivos com status, cor e detalhes."""
        self.device_list.clear()
        devices = self.get_block_devices()

        if not devices and self.boot_device:
            # Informa se apenas o disco de boot está presente
            QMessageBox.information(self, "Lista Vazia", "Apenas o dispositivo de boot foi encontrado. Conecte um novo disco externo.")


        for dev in devices:
            name = dev["name"]
            ro_status = dev["ro_status"]
            size = dev["size"]
            model = dev["model"]
            
            # 1. Determina o status e a cor (Verde para Seguro/RO, Vermelho para Perigoso/RW)
            if ro_status == "1":
                status = "BLOQUEADO (Somente Leitura - RO)"
                color = QColor("green")
            else:
                status = "DESBLOQUEADO (Escrita Habilitada - RW)"
                color = QColor("red")
            
            # 2. Formata o texto para a lista
            item_text = (
                f"/dev/{name} | Status: {status}\n"
                f"   Tamanho: {size} | Modelo: {model}"
            )
            item = QListWidgetItem(item_text)
            
            # 3. Aplica a cor do texto
            item.setForeground(color)
            
            # 4. Armazena o nome do dispositivo como dado do usuário
            item.setData(Qt.ItemDataRole.UserRole, name) 
            self.device_list.addItem(item)
            
        self.update_buttons()

    def set_write_protect(self, ro_state):
        """Executa o comando blockdev --setro/--setrw, desmontando todas as partições primeiro e aplicando a permissão ao dispositivo raiz E a todas as partições."""
        selected_items = self.device_list.selectedItems()
        if not selected_items:
            return

        device_name = selected_items[0].data(Qt.ItemDataRole.UserRole)
        base_dev_path = f"/dev/{device_name}"
        command_arg = "--setro" if ro_state == 1 else "--setrw"
        
        action = "Bloquear Escrita (RO)" if ro_state == 1 else "Desbloquear Escrita (RW)"
        
        reply = QMessageBox.question(self, action, 
            f"Confirmação: Você deseja {action.lower()} no dispositivo {base_dev_path} e em TODAS as suas partições?\n"
            "Todos os pontos de montagem ativos serão desmontados primeiro.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No, 
            QMessageBox.StandardButton.No
        )
        
        if reply == QMessageBox.StandardButton.No:
            return

        # --- 1. LÓGICA DE DESMONTAGEM ---
        unmount_msg = f"Tentativa de desmontagem das partições em {base_dev_path}:\n"
        
        try:
            # Lista as partições e seus pontos de montagem
            # O lsblk -o MOUNTPOINT mostra apenas os pontos de montagem que não estão vazios
            # Usamos o dispositivo raiz para listar todas as partições filhas
            mount_result = subprocess.run(
                ["lsblk", "-n", "-r", "-o", "MOUNTPOINT", base_dev_path],
                capture_output=True, text=True, check=True
            )
            # Filtra linhas vazias e a própria linha raiz do dispositivo, se for o caso
            mount_points = [p.strip() for p in mount_result.stdout.strip().split('\n') if p.strip() and p.strip() != '/']

            if not mount_points:
                unmount_msg += "Nenhuma partição montada encontrada.\n"
                
            for mount_point in mount_points:
                if mount_point:
                    try:
                        # Tenta desmontar com -f (force) e sudo.
                        subprocess.run(
                            ["sudo", "umount", "-f", mount_point],
                            capture_output=True, text=True, check=True, timeout=5
                        )
                        unmount_msg += f" - SUCESSO: Desmontado {mount_point}\n"
                    except subprocess.CalledProcessError as ume:
                        # Pega a última linha do erro, que é geralmente a mais relevante
                        last_error_line = ume.stderr.strip().splitlines()[-1] if ume.stderr else "Erro desconhecido."
                        unmount_msg += f" - FALHA ao desmontar {mount_point}: {last_error_line}\n"
                    except subprocess.TimeoutExpired:
                        unmount_msg += f" - FALHA (Timeout) ao desmontar {mount_point}.\n"

        except Exception as e:
            unmount_msg += f"Erro ao listar pontos de montagem: {e}\n"
        
        # --- 2. IDENTIFICAÇÃO DE TODOS OS DISPOSITIVOS ALVO (Raiz + Partições) ---
        blockdev_msg = f"Tentativa de {action} no dispositivo raiz e partições:\n"
        target_paths = []
        try:
            # Lista o dispositivo raiz e TODAS as suas partições (ex: sdb, sdb1, sdb2)
            part_result = subprocess.run(
                ["lsblk", "-n", "-r", "-o", "NAME", base_dev_path],
                capture_output=True, text=True, check=True
            )
            target_names = [name.strip() for name in part_result.stdout.strip().split('\n') if name.strip()]
            target_paths = [f"/dev/{name}" for name in target_names]
            
        except Exception as e:
            blockdev_msg += f"Erro ao listar dispositivos/partições: {e}\n"
            # Se falhar, pelo menos tenta o dispositivo raiz
            target_paths = [base_dev_path]

        # --- 3. EXECUÇÃO DO BLOCKDEV EM TODOS OS ALVOS ---
        blockdev_success = True
        for dev_path in target_paths:
            try:
                full_command = ["sudo", "blockdev", command_arg, dev_path]
                subprocess.run(
                    full_command,
                    capture_output=True, text=True, check=True
                )
                blockdev_msg += f" - SUCESSO: {command_arg} aplicado a {dev_path}\n"
            except subprocess.CalledProcessError as e:
                # Pega a última linha do erro
                last_error_line = e.stderr.strip().splitlines()[-1] if e.stderr else "Erro desconhecido."
                blockdev_msg += f" - FALHA ao aplicar {command_arg} a {dev_path}:\n   {last_error_line}\n"
                blockdev_success = False
            except Exception as e:
                blockdev_msg += f" - ERRO GERAL ao aplicar a {dev_path}: {e}\n"
                blockdev_success = False

        # --- 4. EXIBIÇÃO DO RESULTADO ---
        final_message = f"{unmount_msg}\n{blockdev_msg}"
        
        if blockdev_success:
            QMessageBox.information(self, "Sucesso Completo", final_message)
        else:
            QMessageBox.critical(self, "Falha Parcial/Total", final_message)
            
        self.load_devices() # Recarrega para mostrar o novo status e cor

if __name__ == "__main__":
    # Verifica as dependências 'lsblk', 'findmnt' e 'umount' (parte do util-linux)
    missing_commands = []
    # Verifica lsblk e findmnt
    for cmd in ["lsblk", "findmnt", "umount"]:
        if not (os.path.exists(f"/usr/bin/{cmd}") or os.path.exists(f"/bin/{cmd}") or os.path.exists(f"/sbin/{cmd}")):
            missing_commands.append(cmd)
        
    if missing_commands:
        print(f"Erro: Os comandos {', '.join(missing_commands)} não foram encontrados.")
        print("Instale o pacote 'util-linux'.")
        sys.exit(1)
        
    app = QApplication(sys.argv)
    manager = BlockDeviceManager()
    manager.show()
    sys.exit(app.exec())
