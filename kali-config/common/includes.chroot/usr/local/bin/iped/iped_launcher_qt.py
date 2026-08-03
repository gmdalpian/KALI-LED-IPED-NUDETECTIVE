#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# iped_launcher_qt.py
# Python/PyQt6 graphical interface in "Wizard" format.
#
import sys
import os
import subprocess
import re # Import regex to extract the base disk name
import shlex 
import gettext
import locale
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QLineEdit, QFileDialog, QMessageBox,
    QFrame, QButtonGroup, QToolButton, QSizePolicy, QStackedWidget
)
from PyQt6.QtGui import QIcon, QFont, QPixmap
from PyQt6.QtCore import Qt, QSize

# --- INTERNATIONALIZATION CONFIGURATION (i18n) ---
APP_NAME = "iped_launcher"
LOCALE_DIR = "/usr/share/locale"

# Attempts to set the locale based on the system environment
try:
    locale.setlocale(locale.LC_ALL, '')
except locale.Error:
    pass

translate = gettext.translation(APP_NAME, LOCALE_DIR, fallback=True)
_ = translate.gettext
# --------------------------------------------------

# --- Description Dictionaries (UPDATED AND TRANSLATED) ---
PROFILE_INFO = {
    "csam_triage": {
        "title": _("CSAM-Triage"), 
        "icon": "security-high",
        "description": _("Profile optimized for detecting <b>CSAM - Child Sexual Abuse Material</b>. Includes AI models using neural networks for detecting unknown files and hash checking for known files, if the IPED hash file is present in the IPED-TRIAGE volume (see user manual). Processes only images and videos, excluding all other files from the case.")
    },
    "triage": {
        "title": _("Triage (Documents, emails, etc.)"),
        "icon": "system-search",
        "description": _("Indexes the content of files from some document formats (office, pdf, html, emails, internet history, etc.) in common user directories. Image and video parsers are disabled. Some folders, such as those containing system files, are not included in the case. Thus, you can do some indexed searches in triage scenarios. The time to complete processing is very unpredictable, highly dependent on the volume of user data.")
    },
    "fastmode": {
        "title": _("FastMode (Quick)"),
        "icon": "preferences-system-performance",
        "description": _("Fastest processing mode to preview data. All features that need file content access are disabled, such as hash calculation, signature analysis, indexing, carving, regex scanning, and thumbnail generation. Basically, it runs an ls on the file system tree. But files are still categorized based on extension, you can preview file content, browse the file system tree, use the image gallery and apply filters based on any file metadata like name, path, size, or MAC times.")
    }
}

TARGET_INFO = {
    "mounted_files": {
        "title": _("Mounted Files (Recommended)"),
        "icon": "folder-remote",
        "description": _("<b>Processes only visible files (Recommended)</b>. Analyzes all files in mounted directories (e.g., /run/media/). It is the fastest and safest option for most triages.")
    },
    "all_disks": {
        "title": _("Disks (Full/Slow)"),
        "icon": "drive-harddisk",
        "description": _("<b>Processes all devices</b>: physical disks, partitions, LDM volumes (RAID), VSS (Shadow Copies), and BitLocker. It is the most complete method, but slower.")
    },
    "manual_dir": {
        "title": _("Select Directory/Image"),
        "icon": "folder-saved-search",
        "description": _("<b>Allows manually choosing</b> a specific directory or a single forensic image file (like .E01, .dd, .vmdk) or cell phone extraction (.ufdr) to be processed.")
    }
}

# Forensic image files filter (UPDATED AND TRANSLATED)
FORENSIC_IMAGE_FILTER = _("Forensic Images (*.E01 *.Ex01 *.e01 *.ex01 *.dd *.raw *.img *.vmdk *.vhd *.AFF *.ufdr *.UFDR);;All Files (*)")

# --- Mount script path ---
MOUNT_SCRIPT_PATH = "/home/kali/mount_disks.sh"

class App(QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle(_("IPED Forensic Processing Wizard"))
        self.setFixedSize(800, 500)

        # --- Executor Script Path ---
        self.script_dir = os.path.dirname(os.path.realpath(__file__))
        self.executor_script = os.path.join(self.script_dir, "iped_executor.sh")

        # --- NEW DEFAULTS ---
        self.selected_profile = "csam_triage" # Default
        self.selected_target = "mounted_files"  # Default

        # --- Variable to store the manual path ---
        self.manual_selected_path = "/run/media" # Pre-filled

        # --- CONTROL VARIABLE FOR THE MOUNT SCRIPT ---
        self.mount_script_run = False

        self.init_ui()
        self.load_stylesheet()
        self.go_to_page_1()
        self.center_window() # Centers the window

    def center_window(self):
        """Centers the window on the main screen."""
        if self.screen():
            screen_geo = self.screen().availableGeometry()
            window_geo = self.frameGeometry()
            self.move(screen_geo.center() - window_geo.center())

    def init_ui(self):
        # --- Load Application Icon ---
        app_icon_path = os.path.join(self.script_dir, "analisador.png")
        if os.path.exists(app_icon_path):
            self.setWindowIcon(QIcon(app_icon_path))
        else:
            print(_("Warning: Icon 'analisador.png' not found. Using default icon."))
            self.setWindowIcon(QIcon.fromTheme("applications-utilities"))

        # --- Central Widget and Main Layout ---
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(0)
        main_layout.setContentsMargins(0, 0, 0, 0)

        # --- Top Title ---
        title_bar = QFrame()
        title_bar.setObjectName("TitleBar")
        title_bar_layout = QHBoxLayout(title_bar)

        self.title_label = QLabel(_("Step 1 of 2: Select Processing Mode"))
        self.title_label.setObjectName("TitleLabel")

        title_bar_layout.addWidget(self.title_label) # Title on the left
        title_bar_layout.addStretch() # Pushes buttons to the right

        self.sys_info_button = QToolButton()
        self.sys_info_button.setIcon(QIcon.fromTheme("utilities-system-monitor")) # Info icon
        self.sys_info_button.setObjectName("SysInfoButton") # For QSS
        self.sys_info_button.setToolTip(_("View System Information"))
        self.sys_info_button.clicked.connect(self.show_system_info)
        title_bar_layout.addWidget(self.sys_info_button)

        self.help_button = QToolButton()
        self.help_button.setIcon(QIcon.fromTheme("help-contents")) # Default help icon
        self.help_button.setObjectName("HelpButton") # For QSS
        self.help_button.setToolTip(_("Open User Manual"))
        self.help_button.clicked.connect(self.open_help_manual)
        title_bar_layout.addWidget(self.help_button)

        main_layout.addWidget(title_bar)

        # --- Page Stack ---
        self.stacked_widget = QStackedWidget()

        # Create and add pages
        self.page_1 = self.create_page_1()
        self.page_2 = self.create_page_2()
        self.stacked_widget.addWidget(self.page_1)
        self.stacked_widget.addWidget(self.page_2)

        main_layout.addWidget(self.stacked_widget)

        # --- Bottom Navigation Bar ---
        nav_bar = QFrame()
        nav_bar.setObjectName("NavBar")
        nav_layout = QHBoxLayout(nav_bar)

        self.exit_button = QPushButton(_("Exit"))
        self.exit_button.clicked.connect(self.close)

        nav_layout.addWidget(self.exit_button)
        nav_layout.addStretch() # Flexible space

        self.back_button = QPushButton(_("Back"))
        self.back_button.clicked.connect(self.go_to_page_1)

        self.next_button = QPushButton(_("Next"))
        self.next_button.setObjectName("NextButton") # Highlighted button
        self.next_button.clicked.connect(self.go_to_page_2)

        self.start_button = QPushButton(_(" Start Processing"))
        self.start_button.setObjectName("StartButton")
        self.start_button.setIcon(QIcon.fromTheme("system-run"))
        self.start_button.clicked.connect(self.start_processing)

        nav_layout.addWidget(self.back_button)
        nav_layout.addWidget(self.next_button)
        nav_layout.addWidget(self.start_button)

        main_layout.addWidget(nav_bar)

    def create_page_1(self):
        """Creates the PROFILE selection page."""
        page = QWidget()
        page_layout = QHBoxLayout(page)
        page_layout.setContentsMargins(0, 0, 0, 0)

        # Left Column (Icons)
        left_col = QFrame()
        left_col.setObjectName("IconColumn")
        left_layout = QVBoxLayout(left_col)
        left_layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        self.profile_group = QButtonGroup(self)
        self.profile_buttons = {}
        for key, info in PROFILE_INFO.items():
            btn = self.create_icon_button(info['icon'])
            btn.setProperty("key", key)
            self.profile_group.addButton(btn)
            self.profile_buttons[key] = btn
            left_layout.addWidget(btn)

        self.profile_buttons["csam_triage"].setChecked(True)
        self.profile_group.buttonToggled.connect(self.update_profile_details)
        page_layout.addWidget(left_col)

        # Right Column (Details)
        right_col = QFrame()
        right_col.setObjectName("DetailsColumn")
        right_layout = QVBoxLayout(right_col)
        right_layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        self.profile_details_icon = QLabel()
        self.profile_details_icon.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.profile_details_title = QLabel()
        self.profile_details_title.setObjectName("DetailsTitle")
        self.profile_details_title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.profile_details_desc = QLabel()
        self.profile_details_desc.setObjectName("DetailsDescription")
        self.profile_details_desc.setWordWrap(True)

        right_layout.addSpacing(20)
        right_layout.addWidget(self.profile_details_icon)
        right_layout.addSpacing(10)
        right_layout.addWidget(self.profile_details_title)
        right_layout.addSpacing(15)
        right_layout.addWidget(self.profile_details_desc)
        right_layout.addStretch()
        page_layout.addWidget(right_col, 1) # '1' makes this column stretch

        return page

    def create_page_2(self):
        """Creates the TARGET selection page."""
        page = QWidget()
        page_layout = QHBoxLayout(page)
        page_layout.setContentsMargins(0, 0, 0, 0)

        # Left Column (Icons)
        left_col = QFrame()
        left_col.setObjectName("IconColumn")
        left_layout = QVBoxLayout(left_col)
        left_layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        self.target_group = QButtonGroup(self)
        self.target_buttons = {}
        for key, info in TARGET_INFO.items():
            btn = self.create_icon_button(info['icon'])
            btn.setProperty("key", key)
            self.target_group.addButton(btn)
            self.target_buttons[key] = btn
            left_layout.addWidget(btn)

        self.target_buttons["mounted_files"].setChecked(True)
        self.target_group.buttonToggled.connect(self.update_target_details)
        page_layout.addWidget(left_col)

        # Right Column (Details)
        right_col = QFrame()
        right_col.setObjectName("DetailsColumn")
        right_layout = QVBoxLayout(right_col)
        right_layout.setAlignment(Qt.AlignmentFlag.AlignTop)

        self.target_details_icon = QLabel()
        self.target_details_icon.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.target_details_title = QLabel()
        self.target_details_title.setObjectName("DetailsTitle")
        self.target_details_title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.target_details_desc = QLabel()
        self.target_details_desc.setObjectName("DetailsDescription")
        self.target_details_desc.setWordWrap(True)

        right_layout.addSpacing(20)
        right_layout.addWidget(self.target_details_icon)
        right_layout.addSpacing(10)
        right_layout.addWidget(self.target_details_title)
        right_layout.addSpacing(15)
        right_layout.addWidget(self.target_details_desc)

        # Manual selection block
        self.manual_frame = QFrame()
        self.manual_frame.setObjectName("ManualFrame")
        manual_layout = QVBoxLayout(self.manual_frame)
        manual_layout.setSpacing(10)

        manual_buttons_layout = QHBoxLayout()

        self.browse_dir_button = QToolButton()
        self.browse_dir_button.setText(_(" Select Directory"))
        self.browse_dir_button.setIcon(QIcon.fromTheme("folder-open"))
        self.browse_dir_button.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.browse_dir_button.clicked.connect(self.browse_directory)
        manual_buttons_layout.addWidget(self.browse_dir_button)

        self.browse_file_button = QToolButton()
        self.browse_file_button.setText(_(" Select Image"))
        self.browse_file_button.setIcon(QIcon.fromTheme("document-open"))
        self.browse_file_button.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.browse_file_button.clicked.connect(self.browse_file)
        manual_buttons_layout.addWidget(self.browse_file_button)

        # ALTERATION 1: Swapped static QLabel for QLineEdit
        self.manual_path_input = QLineEdit(self.manual_selected_path)
        self.manual_path_input.setObjectName("ManualPathInput")
        self.manual_path_input.setPlaceholderText(_("Enter or paste the path here..."))

        manual_layout.addLayout(manual_buttons_layout)
        manual_layout.addWidget(self.manual_path_input)

        self.manual_frame.setVisible(False) # Hidden by default
        right_layout.addWidget(self.manual_frame)

        right_layout.addStretch()
        page_layout.addWidget(right_col, 1)

        return page

    def create_icon_button(self, icon_name):
        """Creates a custom icon button."""
        btn = QToolButton()
        btn.setCheckable(True)
        btn.setAutoExclusive(True)
        btn.setIcon(QIcon.fromTheme(icon_name))
        btn.setIconSize(QSize(48, 48))
        btn.setFixedSize(QSize(70, 70))
        btn.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonIconOnly)
        return btn

    def load_stylesheet(self):
        """Loads QSS to style the application."""
        self.setStyleSheet("""
            QMainWindow {
                background-color: #ffffff;
            }
            QFrame#TitleBar {
                background-color: #37474f; /* Dark gray */
                padding: 10px 15px;
            }
            QLabel#TitleLabel {
                font-size: 14pt;
                font-weight: bold;
                color: white;
            }
            QToolButton#HelpButton, QToolButton#SysInfoButton {
                background-color: transparent;
                border: none;
                border-radius: 4px;
                padding: 5px;
            }
            QToolButton#HelpButton::icon, QToolButton#SysInfoButton::icon {
                color: white;
            }
            QToolButton#HelpButton:hover, QToolButton#SysInfoButton:hover {
                background-color: #546e7a;
            }
            QFrame#NavBar {
                background-color: #eceff1; /* Light gray */
                border-top: 1px solid #cfd8dc;
                padding: 8px;
            }
            QFrame#IconColumn {
                background-color: #f5f5f5; /* Very light gray */
                border-right: 1px solid #e0e0e0;
                padding: 10px;
            }
            QFrame#DetailsColumn {
                background-color: white;
                padding: 15px;
            }
            QToolButton {
                background-color: white;
                border: 2px solid #b0bec5; /* Gray border */
                border-radius: 8px;
                margin: 5px;
            }
            QToolButton:hover {
                border-color: #03a9f4; /* Blue on hover */
            }
            QToolButton:checked {
                background-color: #e3f2fd; /* Light blue background */
                border-color: #03a9f4; /* Strong blue border */
            }
            QLabel#DetailsTitle {
                font-size: 16pt;
                font-weight: bold;
                color: #0277bd; /* Dark blue */
            }
            QLabel#DetailsDescription {
                font-size: 11pt;
                color: #212121; /* Dark text, high contrast */
                line-height: 150%;
            }
            QPushButton {
                font-size: 10pt;
                padding: 8px 15px;
                border-radius: 5px;
                border: 1px solid #b0bec5;
                background-color: white;
                color: #212121;
                min-width: 80px;
            }
            QPushButton:hover {
                background-color: #f5f5f5;
            }
            QPushButton#NextButton {
                font-weight: bold;
                background-color: #039be5; /* Blue */
                color: white;
                border: none;
            }
            QPushButton#StartButton {
                font-weight: bold;
                background-color: #4CAF50; /* Green */
                color: white;
                border: none;
            }
            QFrame#ManualFrame {
                margin-top: 15px;
            }
            QFrame#ManualFrame QToolButton {
                font-size: 10pt;
                padding: 8px;
                background-color: white;
                color: #212121;
                border: 1px solid #b0bec5;
                border-radius: 5px;
                qproperty-iconSize: 20px;
                width: 100%;
            }
            QFrame#ManualFrame QToolButton:hover {
                border-color: #03a9f4;
                background-color: #f5f5f5;
            }
            /* ALTERATION 4: QLineEdit styling */
            QLineEdit#ManualPathInput {
                font-size: 10pt;
                color: #212121;
                background-color: #ffffff;
                border: 1px solid #b0bec5;
                border-radius: 4px;
                padding: 5px;
            }
            QLineEdit#ManualPathInput:focus {
                border-color: #03a9f4; /* Blue when clicked inside */
            }
        """)

    def open_help_manual(self):
        """Opens the PDF manual according to the system language, with a fallback to English."""
        # 1. Detects the environment language (e.g., pt_BR.UTF-8 -> pt_BR)
        lang_env = os.environ.get("LANG", "en_US.UTF-8")
        lang_code = lang_env.split('.')[0] if lang_env else "en_US"

        base_dir = "/home/kali/Desktop/User_Manual"
        
        # 2. Tries to find the manual in the local language
        manual_path = f"{base_dir}/User_Manual_KALI-LED-IPED-NUDETECTIVE_{lang_code}.pdf"

        # 3. Fallback: If it doesn't exist, tries to open the default version in English (en_US)
        if not os.path.exists(manual_path):
            fallback_path = f"{base_dir}/User_Manual_KALI-LED-IPED-NUDETECTIVE_en_US.pdf"
            if os.path.exists(fallback_path):
                manual_path = fallback_path

        # 4. Checks if at least the fallback existed before opening
        if not os.path.exists(manual_path):
            QMessageBox.critical(self, _("Error Opening Manual"),
                                 _("Could not find the manual file at:\n{}").format(manual_path))
            return

        try:
            subprocess.Popen(['xdg-open', manual_path])
        except Exception as e:
            QMessageBox.critical(self, _("Error Opening Manual"),
                                 _("Could not open the manual.\nCheck if 'xdg-open' is installed.\n\nError: {}").format(e))

    def show_system_info(self):
        """Gathers and displays system information in a dialog."""

        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        try:
            info_text = self._gather_system_info()

            QApplication.restoreOverrideCursor()

            dialog = QMessageBox(self)
            dialog.setWindowTitle(_("System Information"))
            dialog.setIcon(QMessageBox.Icon.Information)

            dialog.setTextFormat(Qt.TextFormat.RichText)
            dialog.setStyleSheet("QMessageBox { messagebox-width: 600px; }")
            dialog.setText(f"<pre>{info_text}</pre>")
            dialog.setStandardButtons(QMessageBox.StandardButton.Ok)
            dialog.exec()

        except Exception as e:
            QApplication.restoreOverrideCursor()
            QMessageBox.critical(self, _("Error"), _("Failed to gather system information: {}").format(e))

    def _gather_system_info(self):
        """Executes shell commands to gather information."""
        info = []

        def run_cmd(cmd, check_return_code=True):
            try:
                env = os.environ.copy()
                env['LANG'] = 'C' # Ensures English output internally
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=check_return_code, env=env)
                return result.stdout.strip()
            except subprocess.TimeoutExpired:
                 return _("TIMEOUT: Command '{}' took too long.").format(' '.join(cmd))
            except subprocess.CalledProcessError as e:
                err_msg = e.stderr.strip() if e.stderr else str(e)
                return _("ERROR ({code}): Executing '{cmd}': {err}").format(code=e.returncode, cmd=' '.join(cmd), err=err_msg)
            except FileNotFoundError:
                return _("ERROR: Command '{}' not found.").format(cmd[0])
            except Exception as e:
                return _("Unexpected ERROR: {}").format(e)

        # 1. CPU
        cpu_output = run_cmd(['lscpu'])
        cpu_model = _("Not available")
        if not cpu_output.startswith("ERRO") and not cpu_output.startswith("TIMEOUT"):
            for line in cpu_output.split('\n'):
                if line.startswith("Model name:"):
                    cpu_model = line.split(":", 1)[1].strip()
                    break
        else:
            cpu_model = cpu_output
        info.append(_("CPU: {}").format(cpu_model))

        # 2. RAM
        ram_output = run_cmd(['grep', 'MemTotal', '/proc/meminfo'])
        ram_total = _("Not available")
        if not ram_output.startswith("ERRO") and not ram_output.startswith("TIMEOUT"):
            try:
                mem_kb = int(ram_output.split()[1])
                mem_gb = mem_kb / (1024 * 1024) # Converts KiB to GiB
                ram_total = f"{mem_gb:.1f} GB"
            except Exception as e:
                ram_total = _("Error parsing RAM: {}").format(e)
        else:
            ram_total = ram_output
        info.append(_("Total RAM Memory: {}").format(ram_total))

        # 3. Disks and Partitions
        info.append(_("\nDisks and Partitions (Ignoring boot disk):"))
        info.append("="*40)

        # Calls the centralized utility
        boot_disk_to_ignore = run_cmd(['/usr/local/bin/forensic_utils.sh', '--boot-disk'])
        
        if boot_disk_to_ignore and not boot_disk_to_ignore.startswith("ERRO"):
            info.append(_("(Ignoring boot disk: {})").format(boot_disk_to_ignore))
        else:
            boot_disk_to_ignore = ""
            
        disk_output_raw = run_cmd(['lsblk', '-l', '-o', 'NAME,SIZE,FSTYPE,LABEL,TYPE,MOUNTPOINT'])

        if not disk_output_raw.startswith("ERRO") and not disk_output_raw.startswith("TIMEOUT"):
            filtered_disk_output = []
            header = True
            for line in disk_output_raw.split('\n'):
                if header:
                    filtered_disk_output.append(line)
                    header = False
                    continue

                try:
                    name_col = line.split()[0]
                except IndexError:
                    continue

                if name_col.startswith('loop'):
                    continue

                if boot_disk_to_ignore and name_col.startswith(boot_disk_to_ignore):
                    continue

                filtered_disk_output.append(line)

            if len(filtered_disk_output) <= 1:
                 info.append(_("No disks detected (besides boot disk)."))
            else:
                info.append("\n".join(filtered_disk_output))
        else:
            info.append(disk_output_raw)


        # 4. BitLocker
        info.append(_("\nBitLocker Partitions:"))
        info.append("="*40)
        bitlocker_output = run_cmd(['sudo', 'dislocker-find'], check_return_code=False)

        if bitlocker_output.startswith("ERRO") or bitlocker_output.startswith("TIMEOUT"):
            info.append(bitlocker_output)
        else:
            info.append(bitlocker_output if bitlocker_output else _("No BitLocker partitions found."))

        return "\n".join(info)

    # --- Event and Navigation Functions ---

    def go_to_page_1(self):
        self.stacked_widget.setCurrentIndex(0)
        self.title_label.setText(_("Step 1 of 2: Select Processing Mode"))
        self.back_button.setVisible(False)
        self.next_button.setVisible(True)
        self.start_button.setVisible(False)
        self.update_profile_details(self.profile_buttons[self.selected_profile], True)

    def go_to_page_2(self):
        self.stacked_widget.setCurrentIndex(1)
        self.title_label.setText(_("Step 2 of 2: Select Processing Target"))
        self.back_button.setVisible(True)
        self.next_button.setVisible(False)
        self.start_button.setVisible(True)
        self.update_target_details(self.target_buttons[self.selected_target], True)

    def update_profile_details(self, button, checked):
        if not checked:
            return
        key = button.property("key")
        self.selected_profile = key
        info = PROFILE_INFO.get(key)

        self.profile_details_title.setText(info['title'])
        self.profile_details_desc.setText(info['description'])
        icon_pixmap = QIcon.fromTheme(info['icon']).pixmap(QSize(64, 64))
        self.profile_details_icon.setPixmap(icon_pixmap)

    def update_target_details(self, button, checked):
        if not checked:
            return
        key = button.property("key")
        self.selected_target = key
        info = TARGET_INFO.get(key)

        self.target_details_title.setText(info['title'])
        self.target_details_desc.setText(info['description'])
        icon_pixmap = QIcon.fromTheme(info['icon']).pixmap(QSize(64, 64))
        self.target_details_icon.setPixmap(icon_pixmap)

        self.manual_frame.setVisible(self.selected_target == "manual_dir")

    def _update_manual_path(self, path):
        """Helper function to update the variable and input."""
        # ALTERATION 2: Update QLineEdit instead of QLabel
        if path:
            self.manual_selected_path = path
            self.manual_path_input.setText(path)

    # --- MODIFIED FUNCTION ---
    def _run_mount_script_if_needed(self):
        """
        Calls the mount script in a terminal, if it exists and
        if it hasn't been called in this session yet.
        Returns True if the script was successfully called (or had already been),
        False if there was an error or the script doesn't exist.
        """
        if self.mount_script_run:
            print(_("Mount script already executed in this session."))
            return True

        if not os.path.exists(MOUNT_SCRIPT_PATH):
            # Only warns in the terminal, does not show QMessageBox here
            print(_("Warning: Mount script not found at {}").format(MOUNT_SCRIPT_PATH))
            self.mount_script_run = True # Marks as "run" to not try again
            return True # Continues even without the script

        print(_("Executing mount_disks.sh..."))
        cmd_list = [
            'x-terminal-emulator',
            '-e',
            'bash',
            '-c',
        ]
        
        msg_start = _("Executing script to mount disks and check BitLocker...")
        msg_end = _("Script finished. This terminal will close automatically in 5 seconds (or press Enter to close now).")
        
        # Careful concatenation for bash
        bash_cmd = f"echo '{msg_start}'; "
        bash_cmd += f"{MOUNT_SCRIPT_PATH}; "
        cmd_list.append(bash_cmd)

        success = False
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor) # Wait cursor
        try:
            # Use subprocess.run to wait for the terminal to close
            result = subprocess.run(cmd_list, check=True)
            success = (result.returncode == 0)
        except subprocess.CalledProcessError as e:
            QMessageBox.critical(self, _("Error"), _("Failed to execute the mount script.\nError: {}").format(e))
        except FileNotFoundError:
             QMessageBox.critical(self, _("Error"), _("Command 'x-terminal-emulator' not found.\nCheck if a terminal is set as default."))
        except Exception as e:
            QMessageBox.critical(self, _("Error"), _("Unexpected error calling mount script:\n{}").format(e))
        finally:
             QApplication.restoreOverrideCursor() # Restores the cursor

        self.mount_script_run = True
        return success

    def browse_directory(self):
        """Opens the native dialog to select *only* a directory."""
        if not self._run_mount_script_if_needed():
            return

        path = QFileDialog.getExistingDirectory(
            self,
            _("Select Target Directory"),
            self.manual_selected_path
        )
        self._update_manual_path(path)

    def browse_file(self):
        """Opens the native dialog to select *only* a file."""
        if not self._run_mount_script_if_needed():
            return

        # BUG FIX: Changed '_' to '_filter' so it doesn't conflict with the translation function
        path, _filter = QFileDialog.getOpenFileName(
            self,
            _("Select Image File"),
            self.manual_selected_path,
            FORENSIC_IMAGE_FILTER
        )
        self._update_manual_path(path)

    def start_processing(self):
        # ALTERATION 3: Reads the current path directly from the text field (removes extra spaces)
        self.manual_selected_path = self.manual_path_input.text().strip()

        # 1. Validation
        path = self.manual_selected_path

        if self.selected_target == "manual_dir" and (not path or path == "/run/media"):
            QMessageBox.critical(self, _("Validation Error"),
                                 _("No path selected for manual mode.\nPlease select a directory or file."))
            return

        # 3. Command Construction
        cmd_list = [
            'x-terminal-emulator',
            '-e',
            'bash',
            '-c',
        ]

        bash_cmd = f"{self.executor_script} --profile {self.selected_profile} --target {self.selected_target}"
        
        if self.selected_target == "manual_dir":
            # shlex.quote() wraps the path with single quotes and escapes any 
            # harmful characters, ensuring bash treats it only as text.
            safe_path = shlex.quote(self.manual_selected_path)
            bash_cmd += f" --path {safe_path}"

        # --- UPDATED LINE WITH 10 SECOND TIMEOUT ---
        msg_end = _("Processing finished. This terminal will close automatically in 10 seconds (or press Enter to close now).")
        bash_cmd += f"; echo; echo '{msg_end}'; read -t 10"

        cmd_list.append(bash_cmd)

        try:
            print(_("Executing: {}").format(' '.join(cmd_list)))
            subprocess.Popen(cmd_list)
            self.close() # Closes the GUI to save RAM
        except Exception as e:
            QMessageBox.critical(self, _("Error Starting"),
                                 _("Could not start terminal.\nCheck if 'x-terminal-emulator' is configured.\n\nError: {}").format(e))
if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = App()
    # Centering was moved to the constructor 'self.center_window()'
    window.show()
    sys.exit(app.exec())