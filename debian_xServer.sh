#!/bin/bash
: '
echo text
#https://wiki.debian.org/Debootstrap
#https://www.debian.org/releases/buster/amd64/apds03.de.html
#setxkbmap -layout ch
#scp benutzer@192.168.1.108:/home/benutzer/Schreibtisch/debian_xServer.sh ~
#https://raw.githubusercontent.com/dneuhaus76/public/refs/heads/main/debian_xServer.sh
# sed -i 's/\r//' debian_xServer.sh
#if [ $? -ne 0 ]; then
#read -p "Continue (y/n): " continue_response
$(openssl passwd -6 pwtohash)
'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $SCRIPT_DIR

export myDebugMode="n"
export myUsername="benutzer"
export myComputername="lxqtdebian"
export myPageFile="3G"
export mySite="http://ftp.ch.debian.org/debian/"
export LANG="de_CH.UTF-8"
export LANGUAGE="de"
export log=/mnt/var/log/debianInstall.log
export fname=myPreferencesLXQT.sh
export DEBIAN_FRONTEND=noninteractive

#root check
if [ $EUID -ne 0 ]; then
 echo; echo "run script as root"
 read
 exit 1
fi

#network check
ping -c1 www.google.ch >/dev/null
if [ $? -ne 0 ]; then
  echo; echo "is network connected..."
  read
fi

# disable ipv6 during this installation
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# check current mode 
echo;[ -d /sys/firmware/efi ] && echo "EFI boot on HDD" || echo "Legacy boot on HDD"
echo; lsblk -iT; echo
echo "Enter Device name (/dev/x)"
read -r myDev
#echo "Enter Distribution name (default is ${myDist})"
#read -r myDist

export myDist="${myDist:-bookworm}"
export myDev="${myDev:-/dev/mmcblk0}"
export myPartPrefix="$myDev"

# Check if the device is an eMMC or a hard disk
if [[ $myDev == *mmcblk* ]]; then
    drive_type="eMMC"
    myPartPrefix="${myDev}p"
else
    drive_type="HD"
fi

function NewDiskSchema() {
    # Unmount partitions
    umount -l ${myPartPrefix}* 2 2>/dev/null
    umount -Rl ${myPartPrefix} 2>/dev/null
	sleep 2s
	
    # Cleanup bootsector
    dd if=/dev/zero of="${myDev}" bs=512 count=1

    # Create new partition schema
    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOT | fdisk "${myDev}" >/dev/null
g   # GPT bootsector
n   # New partition
    # Default partition number
    # Default start sector
+512M   # 512M for FAT32 EFI System
    # Default answer for change type
t   # Type
1   # Type 1 is EFI System
n   # New partition
2   # Partition 2
    # Default
    # Default size and default type should be ok for Linux
p   # Print table
w   # Write changes
q   # Quit
EOT

    if [ $? -ne 0 ]; then echo "es sind fehler aufgetreten"; fi

    # Format partitions
    sleep 2s
    mkfs.vfat "${myPartPrefix}1" >/dev/null
      if [ $? -ne 0 ]; then echo "es sind fehler aufgetreten"; fi
    mkfs.ext4 -F "${myPartPrefix}2" >/dev/null
      if [ $? -ne 0 ]; then echo "es sind fehler aufgetreten"; fi

    # Mount partitions for installation
    mount -v "${myPartPrefix}2" /mnt
    sleep 2s
    mkdir -p /mnt/boot/efi
    mount -v "${myPartPrefix}1" /mnt/boot/efi
    sleep 2s

	#Create swapFile
	fallocate -l ${myPageFile} /mnt/swapfile
	chmod 600 /mnt/swapfile
	mkswap /mnt/swapfile
	#echo "" >>/mnt/etc/fstab

    #Check
    if [ $myDebugMode == "y" ]; then
		echo; lsblk "${myDev}" -l
    	echo; echo "bash for corrections... (ctrl+D or exit)"; echo
		bash
	fi
}

function NewOSInstall() {
    apt-get update
    apt install -yqq debian-archive-keyring debian-keyring >/dev/null
    apt install -yqq debootstrap >/dev/null
	debootstrap --no-check-gpg --arch=amd64 ${myDist} /mnt ${mySite} >/dev/null

cat <<EOT >> /mnt/etc/fstab
${myPartPrefix}1  /boot/efi  vfat  umask=0077  0  1
${myPartPrefix}2  /  ext4  defaults,noatime  0  0
/swapfile  none  swap  sw  0  0
EOT

	#Check
	if [ $myDebugMode == "y" ]; then
		#echo; cat /mnt/etc/fstab
		echo; echo "bash for corrections... (ctrl+D or exit)"; echo
		bash
	fi
}

function MyDebianChroot() {
echo "Starte installation..." > ${log}
# Mounte notwendige Dateisysteme
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --rbind /dev /mnt/dev

# treiber von live cd kopieren
if [ ! -d /mnt/lib/firmware ]; then
  mkdir -vp /mnt/lib/firmware >> ${log}
fi
rsync -av --ignore-existing /lib/firmware/ /mnt/lib/firmware/ >> ${log}

# Stage 1 Chroot
# Chroote in das Debian-System
LANG=$LANG chroot /mnt /bin/bash <<CHROOT_SCRIPT
# Innerhalb des Chroots
# keyboard
echo "${LANG} UTF-8" >> /etc/locale.gen
cat <<EOT >/etc/default/locale
LANG="${LANG}"
LANGUAGE="${LANGUAGE}"
EOT

# hostname
echo "${myComputername}" >/etc/hostname

# hosts
cat  <<EOT >/etc/hosts
127.0.0.1 localhost
127.0.1.1 ${myComputername}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOT

# sources
cat <<EOT >/etc/apt/sources.list
deb ${mySite} ${myDist} main non-free-firmware
deb http://security.debian.org/debian-security/ ${myDist}-security main non-free-firmware
EOT

# Aktualisiere apt & firmware
apt update >/dev/null
apt install -yqq firmware-linux firmware-linux-free firmware-linux-nonfree firmware-misc-nonfree

# must have
apt install -yqq nano sudo ssh locales console-setup mc
unlink /etc/localtime; ln -s /usr/share/zoneinfo/Europe/Zurich /etc/localtime
locale-gen ${LANG}
dpkg-reconfigure locales
dpkg-reconfigure keyboard-configuration

#grub & related
apt install -yqq grub-efi-amd64-bin grub-common linux-image-generic
grub-install
update-grub

# Network Manager configuration
apt install -yqq network-manager
systemctl enable NetworkManager.service
#cat <<EOT >/etc/netplan/01-network-manager-all.yaml
#network:
#  version: 2
#  renderer: NetworkManager
#EOT
#chmod 600 /etc/netplan/01-network-manager-all.yaml
# Ende des Chroots
CHROOT_SCRIPT

# Stage 1.5 ausserhalb chroot
# add a user +sudo and a pw
myUserpw='$6$dAStM/uWQ2Xzw9kv$FnRja4AnS4TTb20qPsl3.uYI6FNfqYQaNtqQXaL1VgLSHhTPQulTkiOalGwtUPXWPCRgWQmwIClBiXF0Aotjs.'
useradd --root /mnt -m -s /bin/bash -c "Standard Benutzer" -G adm,sudo -p "${myUserpw}" $myUsername >> ${log}
usermod --root /mnt -aG adm,audio,cdrom,video,netdev,plugdev,users $myUsername >> ${log}

myUserpw='$6$mLioia3OLTLwISfI$vUe5VIV.XJjpHScaQsxsvp.2AFU19NZykEwGF9Hkgmksa4yM/svsuE0IRrylA/rrJiMTIZw2BznFOJWQAXFZn/'
useradd --root /mnt -m -s /bin/bash -c "internet" -G users -p "${myUserpw}" "internet" >> ${log}

# Settings
apt install -yqq curl
gitUrl="https://raw.githubusercontent.com/dneuhaus76/public/refs/heads/main/${fname}"
if curl --output /dev/null --silent --fail -r 0-0 "${gitUrl}"; then
  curl -o /mnt/usr/local/bin/${fname} --silent ${gitUrl}
  echo "Datei heruntergeladen: ${gitUrl}" >> ${log}
fi
echo "current dir: $(pwd)" >> ${log}
if [ -f ${fname} ]; then
  cp -fv "${fname}" /mnt/usr/local/bin/${fname}
  echo "Datei kopiert: ${fname}" >> ${log}
fi

# Stage 2 Chroot
LANG=$LANG chroot /mnt /bin/bash <<CHROOT_SCRIPT
# Installiere meine Applikationen - fix für connman
apt install -yqq xserver-xorg-core lightdm lightdm-settings slick-greeter lxqt lxqt-archiver xrdp chromium thunderbird libwebkit2gtk-4.0-37
apt install -yqq --no-install-recommends xserver-xorg network-manager-gnome
apt purge -yqq connman
apt install -yqq

# Weitere Anpassungen oder Installationen können hier erfolgen
adduser xrdp ssl-cert
cat <<EOT >>/etc/sudoers.d/shutdown
%sudo ALL=(ALL) NOPASSWD: /sbin/shutdown
%sudo ALL=(ALL) NOPASSWD: /sbin/reboot
EOT

# Starte mein Script
bash /usr/local/bin/myPreferencesLXQT.sh

cat <<EOT >>/etc/polkit-1/rules.d/99-shutdown.rules 
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.reboot" ||
         action.id == "org.freedesktop.login1.power-off" ||
         action.id == "org.freedesktop.login1.halt" ||
         action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
         action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
         action.id == "org.freedesktop.login1.halt-multiple-sessions") &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOT

#Checks
echo; cat /etc/apt/sources.list
echo
echo "final chroot checks"
echo

# Ende des Chroots
CHROOT_SCRIPT

	# Bereinige und unmounte
    Sleep 2s
	umount -Rl /mnt
}

# Main
NewDiskSchema
NewOSInstall
MyDebianChroot

# Cleanup
umount -Rl /mnt
echo "[ $(date) ]: Postinstall abgeschlossen" >> ${log}

#Check
#read -p "poweroff? (y/n): " continue_response
#if [ $continue_response == "y" ]; then
	poweroff -p
#fi
