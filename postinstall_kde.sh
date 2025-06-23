#!/bin/bash
#https://blog.infected.systems/posts/2024-10-22-reinstalling-my-laptop-with-ubuntu-autoinstall/
#https://github.com/canonical/autoinstall-desktop/blob/main/autoinstall.yaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $SCRIPT_DIR

export LANG="de_CH.UTF-8"
#export LANGUAGE="de:fr:it:en_US"

log=/var/log/postinstall.log
sname=postinstall.service
fname=postinstall.sh
noLoginMsg="Das System ist während des Postinstalls gesperrt - es wird zum Abschluss heruntergefahren"

echo "--> Postinstall gestartet" > ${log}

# no login while processing script
#echo "${noLoginMsg}" >/etc/nologin

# show config
ip addr >>${log}
ping -4c1 www.google.ch >>${log}

#update itself
if [ -f $fname ]; then
  cp -fv "${fname}" /usr/local/bin/
fi
gitUrl="https://raw.githubusercontent.com/dneuhaus76/public/refs/heads/main/postinstall_kde.sh"
if curl --output /dev/null --silent --fail -r 0-0 "${gitUrl}"; then
  curl -o /usr/local/bin/${fname} --silent ${gitUrl}
  echo "file from: ${gitUrl} download complete" >> ${log}
fi
if ! [ -f /usr/local/bin/${fname} ]; then
  echo "...file not found: /usr/local/bin/${fname}" >> ${log}
fi

#locale aktivieren
LOCALES="de_CH.UTF-8 Fr_CH.UTF-8 it_CH.UTF-8 en_US.UTF-8"
cp -v /etc/locale.gen /etc/locale.gen.bkp
for LOC in $LOCALES; do
  sed -i "/$LOC/s/^# //g" /etc/locale.gen
done
locale-gen
#update-locale LANG=de_CH.UTF-8 LANGUAGE="en:de:fr:it"

varlist="
kde-plasma-desktop sddm sddm-theme-breeze kwin-x11 plasma-nm konsole systemsettings network-manager dolphin ark snapd
language-selector-common fonts-dejavu fonts-freefont-ttf language-pack-en language-pack-de language-pack-fr language-pack-it language-pack-kde-en language-pack-kde-de language-pack-kde-fr language-pack-kde-it
polkitd-pkla xrdp
okular
firefox firefox-locale-en firefox-locale-de firefox-locale-fr firefox-locale-it
thunderbird thunderbird-locale-en thunderbird-locale-de thunderbird-locale-fr thunderbird-locale-it
libreoffice
flameshot
shotcut
vlc
gimp
krita
scribus
inkscape
manuskript
rawtherapee
keepassxc
"

apt update
myInstall="apt install -yq"
for i in $varlist; do
 echo "verarbeite $i:"
 $myInstall "$i" >> ${log}
 if [ $? -ne 0 ]; then
    echo "...Fehler bei Paketinstallation von $i"
    echo "...Fehler bei Paketinstallation von $i" >> ${log}
 fi
done

#snap that have explicit to be installed by snap command
snap install projectlibre >> ${log}
 if [ $? -ne 0 ]; then echo "...Fehler bei Paketinstallation" >> ${log}; fi

#add language packs
$myInstall $(check-language-support -l en) $(check-language-support -l de) $(check-language-support -l fr) $(check-language-support -l it) >> ${log}
 if [ $? -ne 0 ]; then echo "...Fehler bei Paketinstallation" >> ${log}; fi

 #autremove
apt upgrade -yq
apt autoremove -yq

#groups
adduser xrdp ssl-cert >> ${log}

#ufw
ufw enable
ufw allow 22 >> ${log}
ufw allow 3389 >> ${log}

#Service deaktivieren nach Ausführung
#systemctl disable ${sname} >> ${log}

#policy
mkdir -p /etc/polkit-1/localauthority/50-local.d
cat >/etc/polkit-1/localauthority/50-local.d/47-allow-networkd.pkla <<EOF
[Allow Network Control all Users]
Identity=unix-user:*
Action=org.freedesktop.NetworkManager.network-control
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

# Log
ufw status >> ${log}
echo "[ $(date) ]: Postinstall abgeschlossen" >> ${log}

#enable login & poweroff
/bin/rm -f /etc/nologin

#wenn mount in /mnt
#umount -R /mnt
#sleep 1s
#umount -Rl /mnt

#only shutdown if nologin is removed
#if ! [ -f /etc/nologin ]; then poweroff; fi
