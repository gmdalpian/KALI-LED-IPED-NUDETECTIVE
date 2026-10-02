#!/bin/bash

VENV_CPU="/opt/venv_cpu/bin/activate"

sudo bash -c 'source "$1"; shift; exec "$@"' -- "$VENV_CPU" java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped/lib/iped-search-app.jar
