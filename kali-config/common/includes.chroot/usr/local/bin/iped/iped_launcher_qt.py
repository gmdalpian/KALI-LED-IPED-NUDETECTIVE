#!/usr/bin/env python3
#
# iped_launcher_qt.py
# Interface gráfica em Python/PyQt6 no formato "Wizard" (Assistente).
# (Versão que chama scripts backend SEM sudo)
#
import sys
import os
import subprocess
import re # Importar regex para extrair o nome base do disco
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QLineEdit, QFileDialog, QMessageBox,
    QFrame, QButtonGroup, QToolButton, QSizePolicy, QStackedWidget
)
from PyQt6.QtGui import QIcon, QFont, QPixmap
from PyQt6.QtCore import Qt, QSize

# --- Dicionários de Descrição (ATUALIZADOS) ---
PROFILE_INFO = {
    "csam_triage": {
        "title": "CSAM-Triage", # Removido (Recomendado) do título
        "icon": "security-high",
        "description": "Perfil otimizado para detecção de <b>CSAM - Child Sexual Abuse Material (arquivos contendo cenas de abuso sexual infanto-juvenil)</b>. Inclui modelos de IA utilizando redes neurais para detecção de arquivos desconhecidos e verificação de hashes para detectar arquivos conhecidos, caso esteja presente o arquivo de hashes do IPED no volume IPED-TRIAGE (veja manual de uso). Processa somente imagens e vídeos, excluindo todos os demais arquivos do caso."
    },
    "triage": {
        "title": "Triage (Documentos, e-mails etc.)",
        "icon": "system-search",
        "description": "Indexa o conteúdo de arquivos de alguns formatos de documento (office, pdf, html, e-mails, histórico de Internet etc.) em diretórios comuns do usuário. Analisadores (parsers) de imagem e vídeo estão desativados. Algumas pastas, como aquelas que contêm arquivos de sistema, não são incluídas no caso. Assim, você pode fazer algumas buscas indexadas em cenários de triagem. O tempo para concluir o processamento é muito imprevisível, depende muito do volume de dados do usuário."
    },
    "fastmode": {
        "title": "FastMode (Rápido)",
        "icon": "preferences-system-performance",
        "description": "Modo de processamento mais rápido para pré-visualizar dados. Todos os recursos que precisam de acesso ao conteúdo do arquivo são desativados, como cálculo de hash, análise de assinatura, indexação, carving, varredura de regex (regex scanning) e geração de miniaturas. Basicamente, ele executa um ls na árvore do sistema de arquivos. Mas os arquivos ainda são categorizados com base na extensão, você pode pré-visualizar o conteúdo do arquivo, navegar na árvore do sistema de arquivos, usar a galeria de imagens e aplicar filtros com base em quaisquer metadados do arquivo, como nome, caminho, tamanho ou horários MAC (mac times)."
    }
}

TARGET_INFO = {
    "mounted_files": {
        "title": "Arquivos Montados (Recomendado)",
        "icon": "folder-remote",
        "description": "<b>Processa apenas os arquivos visíveis (Recomendado)</b>. Analisa todos os arquivos nos diretórios montados (ex: /media/). É a opção mais rápida e segura para a maioria das triagens."
    },
    "all_disks": {
        "title": "Discos (Completo/Lento)",
        "icon": "drive-harddisk",
        "description": "<b>Processa todos os dispositivos</b>: discos físicos, partições, volumes LDM (RAID), VSS (Shadow Copies) e BitLocker. É o método mais completo, porém mais lento." # Removido asterisco extra
    },
    "manual_dir": {
        "title": "Selecionar Diretório/Imagem",
        "icon": "folder-saved-search",
        "description": "<b>Permite escolher manualmente</b> um diretório específico ou um único arquivo de imagem forense (como .E01, .dd, .vmdk) ou de extração de celulares (.ufdr) para ser processado."
    }
}

# Filtro de arquivos de imagem forense (ATUALIZADO)
FORENSIC_IMAGE_FILTER = "Imagens Forenses (*.E01 *.Ex01 *.e01 *.ex01 *.dd *.raw *.img *.vmdk *.vhd *.AFF *.ufdr *.UFDR);;Todos os Arquivos (*)"

# --- Caminho do script de montagem ---
MOUNT_SCRIPT_PATH = "/home/kali/mount_disks.sh"

class App(QMainWindow):
    def __init__(self):
        super().__init__()

        self.setWindowTitle("Assistente de Processamento Forense IPED")
        self.setFixedSize(800, 500)

        # --- Caminho do Script Executor ---
        self.script_dir = os.path.dirname(os.path.realpath(__file__))
        self.executor_script = os.path.join(self.script_dir, "iped_executor.sh")

        # --- NOVOS PADRÕES ---
        self.selected_profile = "csam_triage" # Padrão
        self.selected_target = "mounted_files"  # Padrão

        # --- Variável para armazenar o caminho manual ---
        self.manual_selected_path = "/media" # Pré-preenchido

        # --- VARIÁVEL DE CONTROLE PARA O SCRIPT DE MONTAGEM ---
        self.mount_script_run = False

        self.init_ui()
        self.load_stylesheet()
        self.go_to_page_1()
        self.center_window() # Centraliza a janela

    def center_window(self):
        """Centraliza a janela na tela principal."""
        if self.screen():
            screen_geo = self.screen().availableGeometry()
            window_geo = self.frameGeometry()
            self.move(screen_geo.center() - window_geo.center())

    def init_ui(self):
        # --- Carregar Ícone da Aplicação ---
        app_icon_path = os.path.join(self.script_dir, "analisador.png")
        if os.path.exists(app_icon_path):
            self.setWindowIcon(QIcon(app_icon_path))
        else:
            print("Aviso: Ícone 'analisador.png' não encontrado. Usando ícone padrão.")
            self.setWindowIcon(QIcon.fromTheme("applications-utilities"))

        # --- Widget Central e Layout Principal ---
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(0)
        main_layout.setContentsMargins(0, 0, 0, 0)

        # --- Título Superior ---
        title_bar = QFrame()
        title_bar.setObjectName("TitleBar")
        title_bar_layout = QHBoxLayout(title_bar)

        self.title_label = QLabel("Passo 1 de 2: Selecione o Modo de Processamento")
        self.title_label.setObjectName("TitleLabel")

        title_bar_layout.addWidget(self.title_label) # Título à esquerda
        title_bar_layout.addStretch() # Empurra os botões para a direita

        self.sys_info_button = QToolButton()
        self.sys_info_button.setIcon(QIcon.fromTheme("utilities-system-monitor")) # Ícone de info
        self.sys_info_button.setObjectName("SysInfoButton") # Para QSS
        self.sys_info_button.setToolTip("Ver Informações do Sistema")
        self.sys_info_button.clicked.connect(self.show_system_info)
        title_bar_layout.addWidget(self.sys_info_button)

        self.help_button = QToolButton()
        self.help_button.setIcon(QIcon.fromTheme("help-contents")) # Ícone padrão de ajuda
        self.help_button.setObjectName("HelpButton") # Para QSS
        self.help_button.setToolTip("Abrir Manual de Uso")
        self.help_button.clicked.connect(self.open_help_manual)
        title_bar_layout.addWidget(self.help_button)

        main_layout.addWidget(title_bar)

        # --- Stack de Páginas ---
        self.stacked_widget = QStackedWidget()

        # Criar e adicionar as páginas
        self.page_1 = self.create_page_1()
        self.page_2 = self.create_page_2()
        self.stacked_widget.addWidget(self.page_1)
        self.stacked_widget.addWidget(self.page_2)

        main_layout.addWidget(self.stacked_widget)

        # --- Barra de Navegação Inferior ---
        nav_bar = QFrame()
        nav_bar.setObjectName("NavBar")
        nav_layout = QHBoxLayout(nav_bar)

        self.exit_button = QPushButton("Sair")
        self.exit_button.clicked.connect(self.close)

        nav_layout.addWidget(self.exit_button)
        nav_layout.addStretch() # Espaço flexível

        self.back_button = QPushButton("Voltar")
        self.back_button.clicked.connect(self.go_to_page_1)

        self.next_button = QPushButton("Próximo")
        self.next_button.setObjectName("NextButton") # Botão de destaque
        self.next_button.clicked.connect(self.go_to_page_2)

        self.start_button = QPushButton(" Iniciar Processamento")
        self.start_button.setObjectName("StartButton")
        self.start_button.setIcon(QIcon.fromTheme("system-run"))
        self.start_button.clicked.connect(self.start_processing)

        nav_layout.addWidget(self.back_button)
        nav_layout.addWidget(self.next_button)
        nav_layout.addWidget(self.start_button)

        main_layout.addWidget(nav_bar)

    def create_page_1(self):
        """Cria a página de seleção de PERFIL."""
        page = QWidget()
        page_layout = QHBoxLayout(page)
        page_layout.setContentsMargins(0, 0, 0, 0)

        # Coluna da Esquerda (Ícones)
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

        # Coluna da Direita (Detalhes)
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
        page_layout.addWidget(right_col, 1) # '1' faz esta coluna esticar

        return page

    def create_page_2(self):
        """Cria a página de seleção de ALVO."""
        page = QWidget()
        page_layout = QHBoxLayout(page)
        page_layout.setContentsMargins(0, 0, 0, 0)

        # Coluna da Esquerda (Ícones)
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

        # Coluna da Direita (Detalhes)
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

        # Bloco de seleção manual
        self.manual_frame = QFrame()
        self.manual_frame.setObjectName("ManualFrame")
        manual_layout = QVBoxLayout(self.manual_frame)
        manual_layout.setSpacing(10)

        manual_buttons_layout = QHBoxLayout()

        self.browse_dir_button = QToolButton()
        self.browse_dir_button.setText(" Selecionar Diretório")
        self.browse_dir_button.setIcon(QIcon.fromTheme("folder-open"))
        self.browse_dir_button.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.browse_dir_button.clicked.connect(self.browse_directory)
        manual_buttons_layout.addWidget(self.browse_dir_button)

        self.browse_file_button = QToolButton()
        self.browse_file_button.setText(" Selecionar Imagem")
        self.browse_file_button.setIcon(QIcon.fromTheme("document-open"))
        self.browse_file_button.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.browse_file_button.clicked.connect(self.browse_file)
        manual_buttons_layout.addWidget(self.browse_file_button)

        self.manual_path_label = QLabel(f"Selecionado: {self.manual_selected_path}")
        self.manual_path_label.setObjectName("ManualPathLabel")
        self.manual_path_label.setWordWrap(True)

        manual_layout.addLayout(manual_buttons_layout)
        manual_layout.addWidget(self.manual_path_label)

        self.manual_frame.setVisible(False) # Oculto por padrão
        right_layout.addWidget(self.manual_frame)

        right_layout.addStretch()
        page_layout.addWidget(right_col, 1)

        return page

    def create_icon_button(self, icon_name):
        """Cria um botão de ícone customizado."""
        btn = QToolButton()
        btn.setCheckable(True)
        btn.setAutoExclusive(True)
        btn.setIcon(QIcon.fromTheme(icon_name))
        btn.setIconSize(QSize(48, 48))
        btn.setFixedSize(QSize(70, 70))
        btn.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonIconOnly)
        return btn

    def load_stylesheet(self):
        """Carrega o QSS para estilizar a aplicação."""
        self.setStyleSheet("""
            QMainWindow {
                background-color: #ffffff;
            }
            QFrame#TitleBar {
                background-color: #37474f; /* Cinza escuro */
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
                background-color: #eceff1; /* Cinza claro */
                border-top: 1px solid #cfd8dc;
                padding: 8px;
            }
            QFrame#IconColumn {
                background-color: #f5f5f5; /* Cinza bem claro */
                border-right: 1px solid #e0e0e0;
                padding: 10px;
            }
            QFrame#DetailsColumn {
                background-color: white;
                padding: 15px;
            }
            QToolButton {
                background-color: white;
                border: 2px solid #b0bec5; /* Borda cinza */
                border-radius: 8px;
                margin: 5px;
            }
            QToolButton:hover {
                border-color: #03a9f4; /* Azul no hover */
            }
            QToolButton:checked {
                background-color: #e3f2fd; /* Fundo azul claro */
                border-color: #03a9f4; /* Borda azul forte */
            }
            QLabel#DetailsTitle {
                font-size: 16pt;
                font-weight: bold;
                color: #0277bd; /* Azul escuro */
            }
            QLabel#DetailsDescription {
                font-size: 11pt;
                color: #212121; /* Texto escuro, alto contraste */
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
                background-color: #039be5; /* Azul */
                color: white;
                border: none;
            }
            QPushButton#StartButton {
                font-weight: bold;
                background-color: #4CAF50; /* Verde */
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
            QLabel#ManualPathLabel {
                font-size: 9pt;
                color: #37474f;
                background-color: #eceff1;
                border-radius: 4px;
                padding: 5px;
            }
        """)

    def open_help_manual(self):
        """Abre o manual PDF em uma nova janela."""
        manual_path = "/home/kali/Desktop/Manual de Uso KALI-LED-IPED-NUDETECTIVE.pdf"

        if not os.path.exists(manual_path):
            QMessageBox.critical(self, "Erro ao Abrir Manual",
                                 f"Não foi possível encontrar o arquivo do manual em:\n{manual_path}")
            return

        try:
            subprocess.Popen(['xdg-open', manual_path])
        except Exception as e:
            QMessageBox.critical(self, "Erro ao Abrir Manual",
                                 f"Não foi possível abrir o manual.\nVerifique se 'xdg-open' está instalado.\n\nErro: {e}")

    def show_system_info(self):
        """Coleta e exibe as informações do sistema em um diálogo."""

        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        try:
            info_text = self._gather_system_info()

            QApplication.restoreOverrideCursor()

            dialog = QMessageBox(self)
            dialog.setWindowTitle("Informações do Sistema")
            dialog.setIcon(QMessageBox.Icon.Information)

            dialog.setTextFormat(Qt.TextFormat.RichText)
            dialog.setStyleSheet("QMessageBox { messagebox-width: 600px; }")
            dialog.setText(f"<pre>{info_text}</pre>")
            dialog.setStandardButtons(QMessageBox.StandardButton.Ok)
            dialog.exec()

        except Exception as e:
            QApplication.restoreOverrideCursor()
            QMessageBox.critical(self, "Erro", f"Falha ao coletar informações do sistema: {e}")

    def _gather_system_info(self):
        """Executa comandos no shell para coletar informações."""
        info = []

        def run_cmd(cmd, check_return_code=True):
            try:
                env = os.environ.copy()
                env['LANG'] = 'C' # Garante saída em inglês
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=check_return_code, env=env)
                return result.stdout.strip()
            except subprocess.TimeoutExpired:
                 return f"TIMEOUT: Comando '{' '.join(cmd)}' demorou demais."
            except subprocess.CalledProcessError as e:
                err_msg = e.stderr.strip() if e.stderr else str(e)
                return f"ERRO ({e.returncode}): Ao executar '{' '.join(cmd)}': {err_msg}"
            except FileNotFoundError:
                return f"ERRO: Comando '{cmd[0]}' não encontrado."
            except Exception as e:
                return f"ERRO Inesperado: {e}"

        # 1. CPU
        cpu_output = run_cmd(['lscpu'])
        cpu_model = "Não disponível"
        if not cpu_output.startswith("ERRO") and not cpu_output.startswith("TIMEOUT"):
            for line in cpu_output.split('\n'):
                if line.startswith("Model name:"):
                    cpu_model = line.split(":", 1)[1].strip()
                    break
        else:
            cpu_model = cpu_output
        info.append(f"CPU: {cpu_model}")

        # 2. RAM
        ram_output = run_cmd(['grep', 'MemTotal', '/proc/meminfo'])
        ram_total = "Não disponível"
        if not ram_output.startswith("ERRO") and not ram_output.startswith("TIMEOUT"):
            try:
                mem_kb = int(ram_output.split()[1])
                mem_gb = mem_kb / (1024 * 1024) # Converte KiB para GiB
                ram_total = f"{mem_gb:.1f} GB"
            except Exception as e:
                ram_total = f"Erro ao parsear RAM: {e}"
        else:
            ram_total = ram_output
        info.append(f"Memória RAM Total: {ram_total}")

        # 3. Discos e Partições
        info.append("\nDiscos e Partições (Ignorando disco de boot):")
        info.append("="*40)

        boot_disk_to_ignore = ""
        try:
            boot_device_full = run_cmd(['findmnt', '-n', '-o', 'SOURCE', '--target', '/run/live/medium'])

            if boot_device_full and not boot_device_full.startswith("ERRO"):
                boot_device_base = os.path.basename(boot_device_full)

                boot_disk_parent = run_cmd(['lsblk', '-n', '-o', 'PKNAME', f'/dev/{boot_device_base}'])

                if boot_disk_parent and not boot_disk_parent.startswith("ERRO"):
                    boot_disk_to_ignore = boot_disk_parent
                    info.append(f"(Ignorando disco de boot: {boot_disk_to_ignore})")
                else:
                    match = re.match(r'([a-zA-Z]+)', boot_device_base)
                    if match:
                         boot_disk_to_ignore = match.group(1)
                         info.append(f"(Ignorando dispositivo de boot: {boot_disk_to_ignore})")
                    else:
                        boot_disk_to_ignore = boot_device_base # Fallback
                        info.append(f"(Ignorando dispositivo de boot: {boot_disk_to_ignore})")
            else:
                 info.append(f"(Aviso: {boot_device_full}, mostrando tudo.)")
                 boot_disk_to_ignore = ""
        except Exception as e:
            info.append(f"(Erro ao identificar disco de boot: {e})")
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
                 info.append("Nenhum disco detectado (além do disco de boot).")
            else:
                info.append("\n".join(filtered_disk_output))
        else:
            info.append(disk_output_raw)


        # 4. BitLocker
        info.append("\nPartições BitLocker:")
        info.append("="*40)
        bitlocker_output = run_cmd(['sudo', 'dislocker-find'], check_return_code=False)

        if bitlocker_output.startswith("ERRO") or bitlocker_output.startswith("TIMEOUT"):
            info.append(bitlocker_output)
        else:
            info.append(bitlocker_output if bitlocker_output else "Nenhuma partição BitLocker encontrada.")

        return "\n".join(info)

    # --- Funções de Evento e Navegação ---

    def go_to_page_1(self):
        self.stacked_widget.setCurrentIndex(0)
        self.title_label.setText("Passo 1 de 2: Selecione o Modo de Processamento")
        self.back_button.setVisible(False)
        self.next_button.setVisible(True)
        self.start_button.setVisible(False)
        self.update_profile_details(self.profile_buttons[self.selected_profile], True)

    def go_to_page_2(self):
        self.stacked_widget.setCurrentIndex(1)
        self.title_label.setText("Passo 2 de 2: Selecione o Alvo do Processamento")
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
        """Função helper para atualizar a variável e o label."""
        if path:
            self.manual_selected_path = path
            self.manual_path_label.setText(f"Selecionado: {path}")

    # --- FUNÇÃO MODIFICADA ---
    def _run_mount_script_if_needed(self):
        """
        Chama o script de montagem em um terminal, se ele existir e
        se ainda não foi chamado nesta sessão.
        Retorna True se o script foi chamado com sucesso (ou já tinha sido),
        False se houve erro ou o script não existe.
        """
        if self.mount_script_run:
            print("Mount script já executado nesta sessão.")
            return True

        if not os.path.exists(MOUNT_SCRIPT_PATH):
            # Apenas avisa no terminal, não mostra QMessageBox aqui
            print(f"Aviso: Script de montagem não encontrado em {MOUNT_SCRIPT_PATH}")
            self.mount_script_run = True # Marca como "rodado" para não tentar de novo
            return True # Continua mesmo sem o script

        print("Executando mount_disks.sh...")
        cmd_list = [
            'x-terminal-emulator',
            '-e',
            'bash',
            '-c',
        ]
        # REMOVIDO sudo daqui
        bash_cmd = f"echo 'Executando script para montar discos e verificar BitLocker...'; "
        bash_cmd += f"{MOUNT_SCRIPT_PATH}; " # Script já tem sudo interno
        bash_cmd += 'echo; echo "Script finalizado. Pressione Enter para fechar este terminal e continuar."; read'
        cmd_list.append(bash_cmd)

        success = False
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor) # Cursor de espera
        try:
            # Usar subprocess.run para esperar o terminal fechar
            result = subprocess.run(cmd_list, check=True)
            success = (result.returncode == 0)
        except subprocess.CalledProcessError as e:
            QMessageBox.critical(self, "Erro", f"Falha ao executar o script de montagem.\nErro: {e}")
        except FileNotFoundError:
             QMessageBox.critical(self, "Erro", "Comando 'x-terminal-emulator' não encontrado.\nVerifique se um terminal está configurado como padrão.")
        except Exception as e:
            QMessageBox.critical(self, "Erro", f"Erro inesperado ao chamar o script de montagem:\n{e}")
        finally:
             QApplication.restoreOverrideCursor() # Restaura o cursor

        self.mount_script_run = True
        return success

    def browse_directory(self):
        """Abre o diálogo nativo para selecionar *apenas* um diretório."""
        if not self._run_mount_script_if_needed():
            return

        path = QFileDialog.getExistingDirectory(
            self,
            "Selecione o Diretório Alvo",
            self.manual_selected_path
        )
        self._update_manual_path(path)

    def browse_file(self):
        """Abre o diálogo nativo para selecionar *apenas* um arquivo."""
        if not self._run_mount_script_if_needed():
            return

        path, _ = QFileDialog.getOpenFileName(
            self,
            "Selecione o Arquivo de Imagem",
            self.manual_selected_path,
            FORENSIC_IMAGE_FILTER
        )
        self._update_manual_path(path)

    # --- FUNÇÃO MODIFICADA ---
    def start_processing(self):
        # 1. Validação
        path = self.manual_selected_path

        if self.selected_target == "manual_dir" and (not path or path == "/media"):
            QMessageBox.critical(self, "Erro de Validação",
                                 "Nenhum caminho foi selecionado para o modo manual.\nPor favor, selecione um diretório ou arquivo.")
            return

        # 2. Confirmação (REMOVIDA)

        # 3. Construção do Comando
        cmd_list = [
            'x-terminal-emulator',
            '-e',
            'bash',
            '-c',
        ]

        # REMOVIDO sudo daqui
        bash_cmd = f"{self.executor_script} --profile {self.selected_profile} --target {self.selected_target}"
        if self.selected_target == "manual_dir":
            bash_cmd += f" --path \"{self.manual_selected_path}\""

        bash_cmd += '; echo; echo "Processamento concluído. Pressione Enter para fechar esta janela."; read'

        cmd_list.append(bash_cmd)

        try:
            print(f"Executando: {' '.join(cmd_list)}")
            subprocess.Popen(cmd_list)
            self.close() # Fecha a GUI para economizar RAM
        except Exception as e:
            QMessageBox.critical(self, "Erro ao Iniciar",
                                 f"Não foi possível iniciar o terminal.\nVerifique se 'x-terminal-emulator' está configurado.\n\nErro: {e}")

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = App()
    # A centralização foi movida para o construtor 'self.center_window()'
    window.show()
    sys.exit(app.exec())