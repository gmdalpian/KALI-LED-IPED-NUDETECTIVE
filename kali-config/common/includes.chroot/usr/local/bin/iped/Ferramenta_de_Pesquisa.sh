#!/bin/bash
sudo PATH=/usr/local/bin/sleuthkit-4.11.1_iped_patch/bin/:$PATH java --module-path /usr/share/openjfx/lib/ --add-modules=javafx.swing,javafx.graphics,javafx.fxml,javafx.media,javafx.controls,javafx.web,javafx.base -jar iped/lib/iped-search-app.jar
