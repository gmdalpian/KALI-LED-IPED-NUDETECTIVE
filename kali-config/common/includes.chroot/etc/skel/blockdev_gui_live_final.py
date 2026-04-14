#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import subprocess
import os
import json
import math
import gettext
import locale
from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout,
    QListWidget, QPushButton, QLabel, QMessageBox,
    QListWidgetItem
)
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QIcon

# --- CONFIGURAÇÃO DE INTERNACIONALIZAÇÃO (i18n) ---
APP_NAME = "blockdev_gui"
LOCALE_DIR = "/usr/share/locale"

# Tenta definir o locale com base no ambiente do sistema
try:
    locale.setlocale(locale.LC_ALL, '')
except locale.Error:
    pass

translate = gettext.translation(APP_NAME, LOCALE_DIR, fallback=True)
_ = translate.gettext
# --------------------------------------------------

# --- CONSTANTES DE CONFIGURAÇÃO ---
ICON_DIR = "/home/kali/Pictures/"
DESKTOP_FILE_PATH = "/home/kali/Desktop/Disk_Shield.desktop"
ICON_GREEN = "disk_shield_green.svg"
ICON_RED = "disk_shield_red.svg"
# Caminho para a biblioteca centralizada
FORENSIC_UTILS = "/home/kali/forensic_utils.sh"
# -----------------------------------

class BlockDeviceManager(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(_("Block Device Lock Manager - LIVE MODE"))
        self.setMinimumWidth(650)
        # Chama a nova lógica de detecção baseada no utilitário centralizado
        self.boot_device = self.get_boot_device()
        self.setup_ui()
        self.load_devices()

    def get_boot_device(self):
        """
        Identifica o dispositivo de bloco raiz do boot Live chamando o utilitário centralizado.
        Isso garante que o disco pai (ex: sdb) seja ignorado corretamente.
        """
        if not os.path.exists(FORENSIC_UTILS):
            print(_("ERROR: Utility {} not found.").format(FORENSIC_UTILS))
            return None

        try:
            # Chama o script centralizado pedindo apenas o nome do disco pai (--boot-disk)
            result = subprocess.run(
                [FORENSIC_UTILS, "--boot-disk"],
                capture_output=True, text=True, check=True,
                env={**os.environ, "LANG": "C"} # Garante compatibilidade de saída
            )
            boot_disk = result.stdout.strip()
            
            if boot_disk and not boot_disk.startswith("ERRO"):
                print(_("Utility identified the boot disk as: {}").format(boot_disk))
                return boot_disk
            return None
            
        except subprocess.CalledProcessError as e:
            print(_("Failed to execute forensic_utils.sh: {}").format(e))
            return None
        except Exception as e:
            print(_("Unexpected error identifying boot: {}").format(e))
            return None

    def setup_ui(self):
        main_layout = QVBoxLayout(self)
        if self.boot_device:
            main_layout.addWidget(QLabel(_("Boot Device (Excluded): /dev/{}").format(self.boot_device)))
        else:
            main_layout.addWidget(QLabel(_("Could not identify the Boot device.")))

        main_layout.addWidget(QLabel(_("Available Block Devices (Green: RO / Red: RW):")))
        self.device_list = QListWidget()
        self.device_list.setSelectionMode(QListWidget.SelectionMode.SingleSelection)
        main_layout.addWidget(self.device_list)

        button_layout = QHBoxLayout()
        self.refresh_button = QPushButton(_("Refresh List"))
        self.refresh_button.clicked.connect(self.load_devices)
        button_layout.addWidget(self.refresh_button)

        self.block_button = QPushButton(_("Block Write (RO)"))
        self.block_button.clicked.connect(lambda: self.set_write_protect(1))
        self.block_button.setEnabled(False) 
        button_layout.addWidget(self.block_button)

        self.unblock_button = QPushButton(_("Allow Write (RW)"))
        self.unblock_button.clicked.connect(lambda: self.set_write_protect(0))
        self.unblock_button.setEnabled(False) 
        button_layout.addWidget(self.unblock_button)
        
        main_layout.addLayout(button_layout)
        self.device_list.itemSelectionChanged.connect(self.update_buttons)

    def _format_size_bytes(self, size_bytes):
        if not size_bytes or size_bytes == 0: return "0 B"
        size = int(size_bytes)
        units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
        i = int(math.floor(math.log(size, 1024)))
        if i >= len(units): i = len(units) - 1
        p = math.pow(1024, i)
        s = round(size / p, 1)
        return f"{s} {units[i]}"

    def _update_desktop_icon(self, is_secure):
        icon_file = ICON_GREEN if is_secure else ICON_RED
        icon_path = ICON_DIR + icon_file
        next_action_name = _("Allow Write") if is_secure else _("Block Write")
        try:
            subprocess.run(["sudo", "sed", "-i", f"s|^Icon=.*|Icon={icon_path}|", DESKTOP_FILE_PATH], check=True)
            subprocess.run(["sudo", "sed", "-i", f"s|^Name=.*|Name={next_action_name}|", DESKTOP_FILE_PATH], check=True)
            subprocess.run(["/bin/bash", "/etc/profile.d/trust_desktop_icons.sh"], check=True)
        except: pass

    def _get_ro_status(self, device_name):
        try:
            result = subprocess.run(["sudo", "blockdev", "--getro", f"/dev/{device_name}"], capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except: return "0"

    def update_buttons(self):
        is_selected = len(self.device_list.selectedItems()) > 0
        self.block_button.setEnabled(is_selected)
        self.unblock_button.setEnabled(is_selected)

    def get_block_devices(self):
        devices = []
        try:
            result = subprocess.run(["lsblk", "-J", "-b", "-o", "NAME,SIZE,MODEL,LABEL,TYPE"], capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            for disk in data.get('blockdevices', []):
                if disk.get('type') == 'disk' and disk.get('name') != self.boot_device:
                    max_partition_size = 0
                    partition_label = _("Unlabeled")
                    for child in disk.get('children', []):
                        if child.get('type') == 'part':
                            size_bytes = int(child.get('size', 0))
                            if size_bytes > max_partition_size:
                                max_partition_size = size_bytes
                                label = child.get('label')
                                partition_label = f"[{label}]" if label else _("Unlabeled")
                    ro_status = self._get_ro_status(disk.get('name'))
                    devices.append({
                        "name": disk.get('name'), "ro_status": ro_status,
                        "size": self._format_size_bytes(disk.get('size')),
                        "model": disk.get('model', 'N/A'), "partition_label": partition_label
                    })
        except Exception as e:
            QMessageBox.critical(self, _("Error"), _("Listing failed: {}").format(e))
        return devices

    def load_devices(self):
        self.device_list.clear()
        devices = self.get_block_devices()
        is_global_secure = True 
        for dev in devices:
            name, ro_status = dev["name"], dev["ro_status"]
            if ro_status == "1":
                status, color = _("BLOCKED (RO)"), QColor("green")
            else:
                status, color = _("UNBLOCKED (RW)"), QColor("red")
                is_global_secure = False
            
            item_text = _("/dev/{name} | Status: {status}\n   Size: {size} | Partition: {partition}").format(
                name=name, status=status, size=dev['size'], partition=dev['partition_label']
            )
            item = QListWidgetItem(item_text)
            item.setForeground(color)
            item.setData(Qt.ItemDataRole.UserRole, name) 
            self.device_list.addItem(item)
        self.update_buttons()
        self.setWindowIcon(QIcon(ICON_DIR + (ICON_GREEN if is_global_secure else ICON_RED)))
        self._update_desktop_icon(is_global_secure)

    def _get_all_targets(self, device_name):
        try:
            result = subprocess.run(["lsblk", "-n", "-r", "-o", "NAME", f"/dev/{device_name}"], capture_output=True, text=True, check=True)
            return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        except: return [device_name]

    def _unmount_target(self, target_name):
        try:
            subprocess.run(["sudo", "umount", "-f", f"/dev/{target_name}"], capture_output=True, text=True, check=True)
            return _("Success: /dev/{} unmounted.").format(target_name)
        except subprocess.CalledProcessError as e:
            if "not mounted" in e.stderr or e.returncode == 32: 
                return _("Ignored: /dev/{} was not mounted.").format(target_name)
            return _("Failed on /dev/{}: {}").format(target_name, e.stderr.strip())

    def set_write_protect(self, ro_state):
        selected_items = self.device_list.selectedItems()
        if not selected_items: return
        device_name = selected_items[0].data(Qt.ItemDataRole.UserRole)
        command_arg = "--setro" if ro_state == 1 else "--setrw"
        
        action_en = "Block Write (RO)" if ro_state == 1 else "Allow Write (RW)"
        action = _(action_en)
        
        msg = _("Do you want to {action} on /dev/{device}?").format(action=action.lower(), device=device_name)
        reply = QMessageBox.question(self, action, msg, QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        
        if reply == QMessageBox.StandardButton.No: return
        targets = self._get_all_targets(device_name)
        log_messages = [_("\n--- Unmounting ---")]
        for target in targets: log_messages.append(self._unmount_target(target))
        log_messages.append(_("\n--- Permission ---"))
        success_count = 0
        for target in targets:
            try:
                subprocess.run(["sudo", "blockdev", command_arg, f"/dev/{target}"], check=True)
                log_messages.append(_("Success: /dev/{}").format(target))
                success_count += 1
            except: pass
        self.load_devices()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    manager = BlockDeviceManager()
    manager.show()
    sys.exit(app.exec())