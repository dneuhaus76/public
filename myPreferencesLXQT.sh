#!/bin/bash

# my login config no varialbe translation
cat <<'EOT' >>/etc/bash.bashrc
echo; echo "$USER ($LANGUAGE) on $HOSTNAME"; hostname -I; id
ls -l /etc/localtime | awk '{print $NF}'
EOT

file=/etc/xdg/lxqt/lxqt.conf
cp -nv $file ${file}.orig
cat <<EOT > $file
[General]
icon_theme=oxygen
icon_follow_color_scheme=false
theme=ambiance

[Qt]
style=cleanlooks
EOT

file=/etc/xdg/lxqt/panel.conf
cp -nv $file ${file}.orig
cat <<EOT > $file
[General]
iconTheme=Papirus-Dark

[kbindicator]
alignment=Right
show_caps_lock=false
show_layout=true
show_num_lock=false
show_scroll_lock=false
type=kbindicator

[quicklaunch]
alignment=Left
apps\1\desktop=/usr/share/applications/pcmanfm-qt.desktop
apps\2\desktop=/usr/share/applications/qterminal.desktop
apps\3\desktop=/usr/share/applications/featherpad.desktop
apps\size=3
type=quicklaunch

[quicklaunch2]
alignment=left
apps\1\desktop=/usr/share/applications/lxqt-leave.desktop
apps\size=1
type=quicklaunch

[panel1]
plugins=mainmenu, showdesktop, desktopswitch, quicklaunch, taskbar, kbindicator, tray, statusnotifier, mount, volume, worldclock, quicklaunch2

[taskbar]
buttonWidth=200
raiseOnCurrentDesktop=true
EOT

file=/etc/xdg/lxqt/lxqt-powermanagement.conf
cp -nv $file ${file}.orig
cat <<EOT > $file
[General]
iconType=4
EOT

file=/etc/xdg/pcmanfm-qt/lxqt/settings.conf
cp -nv $file ${file}.orig
cat <<EOT > $file
[Desktop]
DesktopShortcuts=Home, Trash
Wallpaper=/usr/share/lxqt/wallpapers/plasma_arch.png
WallpaperMode=zoom

[FolderView]
Mode=detailed

[Window]
PathBarButtons=false
EOT

file=/etc/xdg/featherpad/fp.conf
if [ ! -d "$(dirname "$file")" ]; then
	mkdir -p "$(dirname "$file")"
fi
cp -nv $file ${file}.orig
cat <<EOT > $file
[text]
lineNumbers=true
autoBracket=true
EOT

file=/usr/share/applications/dnNotebookLM.desktop
cat <<EOT > $file
[Desktop Entry]
Type=Application
Name=NotebookLM
Exec=/usr/bin/chromium --app="https://notebooklm.google.com/"
Icon=emblem-debian-symbolic
Categories=LXQt;Network;
EOT

file=/usr/share/applications/dnGemini.desktop
cat <<EOT > $file
[Desktop Entry]
Type=Application
Name=Gemini
Exec=/usr/bin/chromium --app="https://gemini.google.com/app?hl=de"
Icon=emblem-debian-symbolic
Categories=LXQt;Network;
EOT

file=/usr/share/applications/dnChatgpt.desktop
cat <<EOT > $file
[Desktop Entry]
Type=Application
Name=Chatgpt
Exec=/usr/bin/chromium --app="https://chatgpt.com/"
Icon=emblem-debian-symbolic
Categories=LXQt;Network;
EOT

file=/usr/share/applications/dnChromium-private.desktop
cat <<EOT > $file
[Desktop Entry]
Version=1.0
Name=Chromium Private
Comment=Access the Internet
Exec=/usr/bin/chromium %U -incognito
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=chromium
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml_xml;application/x-mimearchive;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=chromium
StartupNotify=true
Keywords=browser
EOT
