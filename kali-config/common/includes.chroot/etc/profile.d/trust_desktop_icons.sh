#/bin/bash
# Evita as mensagens do XFCe ao executar icones na area de trabalho
for f in ~/Desktop/*.desktop; do chmod +x "$f" && gio set "$f" metadata::xfce-exe-checksum "$(sha256sum "$f" | awk '{print $1}')"; done
