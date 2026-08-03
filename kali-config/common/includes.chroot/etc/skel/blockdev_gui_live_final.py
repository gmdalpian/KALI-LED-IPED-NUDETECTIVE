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

# --- INTERNATIONALIZATION (i18n) CONFIGURATION ---
APP_NAME = "blockdev_gui"
LOCALE_DIR = "/usr/share/locale"

# Try to set the locale based on the system environment
try:
    locale.setlocale(locale.LC_ALL, '')
except locale.Error:
    pass

translate = gettext.translation(APP_NAME, LOCALE_DIR, fallback=True)
_ = translate.gettext
# --------------------------------------------------

# --- CONFIGURATION CONSTANTS ---
ICON_DIR = "/home/kali/Pictures/"
DESKTOP_FILE_PATH = "/home/kali/Desktop/Disk_Shield.desktop"
ICON_GREEN = "disk_shield_green.svg"
ICON_RED = "disk_shield_red.svg"
# Path to the centralized library
FORENSIC_UTILS = "/usr/local/bin/forensic_utils.sh"
# -----------------------------------

class BlockDeviceManager(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(_("Block Device Lock Manager - LIVE MODE"))
        self.setMinimumWidth(650)
        
        # Calls the detection logic based on the centralized utility
        self.boot_device = self.get_boot_device()
        # Maps all components derived from the boot device to avoid Ventoy conflicts
        self.boot_components = self.get_boot_components(self.boot_device)
        
        self.setup_ui()
        self.load_devices()

    def get_boot_device(self):
        """
        Identifies the root block device of the Live boot by calling the centralized utility.
        """
        if not os.path.exists(FORENSIC_UTILS):
            print(_("ERROR: Utility {} not found.").format(FORENSIC_UTILS))
            return None

        try:
            # Calls the centralized script requesting only the parent disk name (--boot-disk)
            result = subprocess.run(
                [FORENSIC_UTILS, "--boot-disk"],
                capture_output=True, text=True, check=True,
                env={**os.environ, "LANG": "C"} # Ensures output compatibility
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

    def get_boot_components(self, boot_disk):
        """
        Retrieves all KNAMEs associated with the boot disk (e.g., sdb1, dm-0)
        to prevent locking Ventoy mappings or Live system partitions.
        """
        components = set()
        if not boot_disk:
            return components
            
        try:
            result = subprocess.run(
                ["lsblk", "-n", "-r", "-o", "KNAME", f"/dev/{boot_disk}"],
                capture_output=True, text=True, check=True
            )
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    components.add(line.strip())
        except Exception as e:
            print(_("Failed to get boot components: {}").format(e))
            components.add(boot_disk) # Fallback to at least block the parent disk
            
        return components

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
        
        # Base text (fallback) in English, used as a key in gettext
        default_name = "Allow Write" if is_secure else "Block Write"
        
        # Dynamically translated text for the current language
        translated_name = _(default_name)
        
        # Captures the current language code (e.g., extracts 'pt_BR' from 'pt_BR.UTF-8')
        lang_env = os.environ.get('LANG', 'en_US.UTF-8')
        current_lang = lang_env.split('.')[0]
        
        try:
            # 1. Updates the icon path
            subprocess.run(["sudo", "sed", "-i", rf"s|^Icon=.*|Icon={icon_path}|", DESKTOP_FILE_PATH], check=True)
            
            # 2. Updates the default Name key (keeping the English fallback)
            subprocess.run(["sudo", "sed", "-i", rf"s|^Name=.*|Name={default_name}|", DESKTOP_FILE_PATH], check=True)
            
            # 3. Updates only the key corresponding to the current language (e.g., Name[pt_BR]=Permitir Escrita)
            subprocess.run(["sudo", "sed", "-i", rf"s|^Name\[{current_lang}\]=.*|Name[{current_lang}]={translated_name}|", DESKTOP_FILE_PATH], check=True)
            
            # Revalidates the shortcut in the XFCE environment
            subprocess.run(["/bin/bash", "/etc/profile.d/trust_desktop_icons.sh"], check=True)
        except Exception as e: 
            print(_("Error updating desktop shortcut: {}").format(e))

    def _get_ro_status(self, kname):
        try:
            # Safe operations using the Kernel Name (e.g., /dev/dm-0)
            result = subprocess.run(["sudo", "blockdev", "--getro", f"/dev/{kname}"], capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except: return "0"

    def update_buttons(self):
        is_selected = len(self.device_list.selectedItems()) > 0
        self.block_button.setEnabled(is_selected)
        self.unblock_button.setEnabled(is_selected)

    def get_block_devices(self):
        devices = []
        seen_knames = set()  # Set to track and deduplicate devices
        
        try:
            # Added KNAME to safely map devices generated by dm/ldm
            result = subprocess.run(["lsblk", "-J", "-b", "-o", "NAME,KNAME,SIZE,MODEL,LABEL,TYPE"], capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            
            def extract_devices(nodes):
                for node in nodes:
                    name = node.get('name')
                    kname = node.get('kname', name)
                    
                    # Prevents processing of any component related to the boot device (e.g., sdb1, dm-0 from Ventoy)
                    if name in self.boot_components or kname in self.boot_components:
                        continue
                        
                    # Prevents duplicate entries for volumes spanning multiple disks (e.g., RAID/Spanned LDM)
                    if kname in seen_knames:
                        continue
                        
                    # Filter out devices with no media (e.g., empty SD card readers or CD/DVD drives)
                    device_size = node.get('size')
                    if not device_size or int(device_size) == 0:
                        continue
                    
                    # Mark this device as seen
                    seen_knames.add(kname)
                    
                    node_type = node.get('type')
                    
                    # "dm" is the Device Mapper (LVM, LUKS, etc.)
                    # "ldm" is used for Windows Dynamic Disks handled by ldmtool
                    if node_type in ['disk', 'dm', 'ldm']:
                        partition_label = _("Unlabeled")
                        if node_type == 'disk':
                            max_partition_size = 0
                            for child in node.get('children', []):
                                if child.get('type') == 'part':
                                    size_bytes = int(child.get('size', 0))
                                    if size_bytes > max_partition_size:
                                        max_partition_size = size_bytes
                                        label = child.get('label')
                                        partition_label = f"[{label}]" if label else _("Unlabeled")
                        elif node_type in ['dm', 'ldm']:
                            # Mapped and ldm devices usually host the label directly
                            label = node.get('label')
                            partition_label = f"[{label}]" if label else _("Unlabeled")

                        ro_status = self._get_ro_status(kname)
                        devices.append({
                            "name": name,
                            "kname": kname,
                            "ro_status": ro_status,
                            "size": self._format_size_bytes(node.get('size')),
                            "model": node.get('model') or 'N/A', 
                            "partition_label": partition_label
                        })
                        
                    # Recursion: searches for dm/ldm devices encapsulated by others
                    if 'children' in node:
                        extract_devices(node.get('children', []))
            
            extract_devices(data.get('blockdevices', []))
        except Exception as e:
            QMessageBox.critical(self, _("Error"), _("Listing failed: {}").format(e))
        return devices

    def load_devices(self):
        self.device_list.clear()
        devices = self.get_block_devices()
        is_global_secure = True 
        for dev in devices:
            name, kname, ro_status = dev["name"], dev["kname"], dev["ro_status"]
            if ro_status == "1":
                status, color = _("BLOCKED (RO)"), QColor("green")
            else:
                status, color = _("UNBLOCKED (RW)"), QColor("red")
                is_global_secure = False
            
            # Shows NAME in the UI, but saves KNAME for interactions
            item_text = _("{name} | Status: {status}\n   Size: {size} | Partition: {partition}").format(
                name=name, status=status, size=dev['size'], partition=dev['partition_label']
            )
            item = QListWidgetItem(item_text)
            item.setForeground(color)
            item.setData(Qt.ItemDataRole.UserRole, kname)  # Primary management ID
            item.setData(Qt.ItemDataRole.UserRole + 1, name) # Friendly name
            self.device_list.addItem(item)
            
        self.update_buttons()
        self.setWindowIcon(QIcon(ICON_DIR + (ICON_GREEN if is_global_secure else ICON_RED)))
        self._update_desktop_icon(is_global_secure)

    def _get_all_targets(self, kname):
        try:
            # Returns via Kernel Name instead of NAME, ensuring compatibility
            result = subprocess.run(["lsblk", "-n", "-r", "-o", "KNAME", f"/dev/{kname}"], capture_output=True, text=True, check=True)
            return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        except: return [kname]

    def _unmount_target(self, target_kname):
        try:
            subprocess.run(["sudo", "umount", "-f", f"/dev/{target_kname}"], capture_output=True, text=True, check=True)
            return _("Success: /dev/{} unmounted.").format(target_kname)
        except subprocess.CalledProcessError as e:
            if "not mounted" in e.stderr or e.returncode == 32: 
                return _("Ignored: /dev/{} was not mounted.").format(target_kname)
            return _("Failed on /dev/{}: {}").format(target_kname, e.stderr.strip())

    def set_write_protect(self, ro_state):
        selected_items = self.device_list.selectedItems()
        if not selected_items: return
        
        kname = selected_items[0].data(Qt.ItemDataRole.UserRole)
        name = selected_items[0].data(Qt.ItemDataRole.UserRole + 1)
        
        command_arg = "--setro" if ro_state == 1 else "--setrw"
        
        action_en = "Block Write (RO)" if ro_state == 1 else "Allow Write (RW)"
        action = _(action_en)
        
        msg = _("Do you want to {action} on {device}?").format(action=action.lower(), device=name)
        reply = QMessageBox.question(self, action, msg, QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        
        if reply == QMessageBox.StandardButton.No: return
        targets = self._get_all_targets(kname)
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