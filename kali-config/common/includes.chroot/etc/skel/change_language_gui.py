#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import subprocess
import os
import gettext
from PyQt6.QtWidgets import (
    QApplication, QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QRadioButton, QPushButton, QMessageBox, QButtonGroup,
    QFrame
)
from PyQt6.QtCore import Qt, QSize
from PyQt6.QtGui import QIcon

# --- CONFIGURAÇÃO DE INTERNACIONALIZAÇÃO (i18n) ---
APP_NAME = "change_language"
LOCALE_DIR = "/usr/share/locale"

t = gettext.translation(APP_NAME, localedir=LOCALE_DIR, fallback=True)
_ = t.gettext

# --- CONSTANTES ---
DIRETORIO_BANDEIRAS = "/home/kali/Pictures/flags"
ARQUIVO_LOCALE_CONF = "/etc/locale.conf"
ICON_SYSTEM = "preferences-desktop-locale"

IDIOMAS = {
    "en_US.UTF-8": {"nome": _("English (US)"), "icone": "us.svg"},
    "pt_BR.UTF-8": {"nome": _("Português (Brasil)"), "icone": "br.svg"}
#    "es_ES.UTF-8": {"nome": _("Español"), "icone": "es.svg"}
}

class LanguageSelector(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(_("System Language Selector"))
        self.setWindowIcon(QIcon.fromTheme(ICON_SYSTEM))
        self.setMinimumWidth(450)
        self.setup_ui()
        self.load_stylesheet()
        self.center_window()

    def center_window(self):
        if self.screen():
            screen_geo = self.screen().availableGeometry()
            window_geo = self.frameGeometry()
            self.move(screen_geo.center() - window_geo.center())

    def load_stylesheet(self):
        """Aplica o tema claro e profissional compatível com o IPED Launcher"""
        self.setStyleSheet("""
            QWidget {
                background-color: #ffffff;
                color: #212121;
            }
            QFrame#InfoFrame, QFrame#SelectionFrame {
                background-color: #f5f5f5;
                border: 1px solid #cfd8dc;
                border-radius: 8px;
            }
            QLabel {
                font-size: 11pt;
                color: #212121;
                border: none;
            }
            QLabel#SectionTitle {
                font-weight: bold;
                font-size: 12pt;
                color: #0277bd;
                margin-bottom: 5px;
            }
            QLabel#CurrentLangValue {
                font-weight: bold;
                font-size: 12pt;
            }
            QRadioButton {
                font-size: 12pt;
                color: #212121;
                padding: 8px;
                font-weight: 500;
            }
            QPushButton#ApplyButton {
                font-size: 11pt;
                font-weight: bold;
                padding: 10px 20px;
                border-radius: 5px;
                background-color: #4CAF50;
                color: white;
                border: none;
            }
            QPushButton#ApplyButton:hover {
                background-color: #43a047;
            }
        """)

    def setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(15)

        # --- SEÇÃO: IDIOMA ATUAL ---
        idioma_atual_cod = self.descobrir_idioma_atual()
        info_atual = IDIOMAS.get(idioma_atual_cod, {"nome": _("Unknown"), "icone": ""})

        info_frame = QFrame()
        info_frame.setObjectName("InfoFrame")
        info_layout = QHBoxLayout(info_frame)
        info_layout.setContentsMargins(15, 15, 15, 15)
        
        lbl_info = QLabel(_("Current Language:"))
        lbl_info.setStyleSheet("font-weight: bold; color: #546e7a;")
        
        self.lbl_current_flag = QLabel()
        caminho_flag = os.path.join(DIRETORIO_BANDEIRAS, info_atual["icone"])
        if os.path.exists(caminho_flag):
            self.lbl_current_flag.setPixmap(QIcon(caminho_flag).pixmap(QSize(32, 24)))
        
        self.lbl_current_name = QLabel(info_atual["nome"])
        self.lbl_current_name.setObjectName("CurrentLangValue")
        
        info_layout.addWidget(lbl_info)
        info_layout.addSpacing(10)
        info_layout.addWidget(self.lbl_current_flag)
        info_layout.addWidget(self.lbl_current_name)
        info_layout.addStretch()
        layout.addWidget(info_frame)

        # --- SEÇÃO: SELEÇÃO ---
        titulo_sel = QLabel(_("Select the new default language:"))
        titulo_sel.setObjectName("SectionTitle")
        layout.addWidget(titulo_sel)

        selection_frame = QFrame()
        selection_frame.setObjectName("SelectionFrame")
        selection_layout = QVBoxLayout(selection_frame)
        selection_layout.setContentsMargins(15, 15, 15, 15)
        selection_layout.setSpacing(10)

        self.grupo_botoes = QButtonGroup(self)
        self.botoes_radio = {}

        for codigo, info in IDIOMAS.items():
            radio = QRadioButton(info["nome"])
            radio.setProperty("codigo", codigo)
            
            caminho_icone = os.path.join(DIRETORIO_BANDEIRAS, info["icone"])
            if os.path.exists(caminho_icone):
                radio.setIcon(QIcon(caminho_icone))
                radio.setIconSize(QSize(32, 24))
            
            if codigo == idioma_atual_cod:
                radio.setChecked(True)
                
            self.grupo_botoes.addButton(radio)
            self.botoes_radio[codigo] = radio
            selection_layout.addWidget(radio)

        layout.addWidget(selection_frame)
        layout.addStretch()

        # --- SEÇÃO: BOTÃO ---
        button_layout = QHBoxLayout()
        self.botao_aplicar = QPushButton(_(" Apply and Save Changes"))
        self.botao_aplicar.setObjectName("ApplyButton")
        self.botao_aplicar.setIcon(QIcon.fromTheme("emblem-system"))
        self.botao_aplicar.setCursor(Qt.CursorShape.PointingHandCursor)
        self.botao_aplicar.clicked.connect(self.aplicar_idioma)
        
        button_layout.addStretch()
        button_layout.addWidget(self.botao_aplicar)
        layout.addLayout(button_layout)

    def descobrir_idioma_atual(self):
        try:
            if os.path.exists(ARQUIVO_LOCALE_CONF):
                with open(ARQUIVO_LOCALE_CONF, "r") as f:
                    conteudo = f.read()
                    for codigo in IDIOMAS.keys():
                        if codigo in conteudo: return codigo
            result = subprocess.run(['locale', 'LANG'], capture_output=True, text=True)
            lang = result.stdout.strip().split('=')[-1]
            return lang if lang in IDIOMAS else "en_US.UTF-8"
        except: return "en_US.UTF-8"

    def aplicar_idioma(self):
        botao_selecionado = self.grupo_botoes.checkedButton()
        if not botao_selecionado: return

        codigo_idioma = botao_selecionado.property("codigo")
        nome_idioma = botao_selecionado.text()
        
        # Define os conteúdos exatos e separados para cada ficheiro
        conteudo_locale_conf = f"LANG={codigo_idioma}\n"

        try:
            # Passa o texto diretamente via 'input' e esconde o output no DEVNULL.
            # Isto elimina o uso do 'echo -e' e do 'shell=True', resolvendo o bug.
            subprocess.run(["sudo", "tee", ARQUIVO_LOCALE_CONF], 
                           input=conteudo_locale_conf.encode('utf-8'), 
                           stdout=subprocess.DEVNULL, 
                           check=True)                           

            msg = _("Language changed to {lang}.\n\nDo you want to restart the graphical environment (X) now?").format(lang=nome_idioma)
            reply = QMessageBox.question(self, _("Success"), msg, QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)

            if reply == QMessageBox.StandardButton.Yes:
                subprocess.run(["sudo", "systemctl", "restart", "lightdm"])
            else:
                self.close()
        except Exception as e:
            QMessageBox.critical(self, _("Error"), _("Failed to save settings: {}").format(e))

if __name__ == "__main__":
    app = QApplication(sys.argv)
    janela = LanguageSelector()
    janela.show()
    sys.exit(app.exec())
