#/bin/bash
xfconf-query --channel xfce4-desktop --list | grep last-image | while read path; do
	xfconf-query --channel xfce4-desktop --property $path --set "/home/kali/Pictures/plano_de_fundo.jpg"
done

