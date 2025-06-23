#!/bin/bash
: '
echo text
#https://wiki.debian.org/Debootstrap
#setxkbmap -layout ch
#if [ $? -ne 0 ]; then
#read -p "Continue (y/n): " continue_response
$(openssl passwd -6 pwtohash)
'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $SCRIPT_DIR

export myDebugMode="n"
export myUsername="benutzer"
export mySite="http://archive.ubuntu.com/ubuntu/"
export LANG="de_CH.UTF-8"
#export LANGUAGE="en:de:fr:it"
export fname=postinstall.sh
export sname=postinstall.service
export log=/var/log/postinstall.log
export DEBIAN_FRONTEND=noninteractive

#root check
if [ $EUID -ne 0 ]; then
 echo; echo "Script muss mit root rechten gestartet werden"
 read
 exit 1
fi

# disable ipv6 during this installation
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null

echo; echo "Enter Computername (kbuntu)"
read -r myComputername

#echo "Enter Distribution name (default is ${myDist})"
#read -r myDist

# check current mode
echo;[ -d /sys/firmware/efi ] && echo "EFI boot on HDD" || echo "Legacy boot on HDD"
echo; lsblk

echo; echo "Enter Device name (/dev/x)"
read -r myDev

export myComputername="${myComputername:-kubuntu}"
export myDist="${myDist:-noble}"
export myDev="${myDev:-/dev/sda}"
export myPartPrefix="$myDev"

# Check if the device is an eMMC or a hard disk
if [[ $myDev == */sd* ]]; then
    drive_type="usb?"
else
    drive_type="disk"
    myPartPrefix="${myDev}p"
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

    if [ $? -ne 0 ]; then echo "...aufgetreten"; fi

    # Format partitions
    sleep 2s
    mkfs.vfat "${myPartPrefix}1" >/dev/null
     if [ $? -ne 0 ]; then echo "...aufgetreten"; fi
    mkfs.ext4 -F "${myPartPrefix}2" >/dev/null
     if [ $? -ne 0 ]; then echo "...aufgetreten"; fi

    # Mount partitions for installation
    mount "${myPartPrefix}2" /mnt
    sleep 2s
    mkdir -p /mnt/boot/efi
    mount "${myPartPrefix}1" /mnt/boot/efi
    sleep 2s
}

function NewOSInstall() {
    apt-get update
    apt install -yqq ubuntu-keyring >/dev/null
    apt install -yqq debootstrap >/dev/null
	debootstrap --no-check-gpg --arch=amd64 ${myDist} /mnt ${mySite} >/dev/null

cat <<EOT >> /mnt/etc/fstab
${myPartPrefix}1  /boot/efi  vfat  umask=0077  0  1
${myPartPrefix}2  /  ext4  defaults,noatime  0  0
EOT

	#Check
	if [ $myDebugMode == "y" ]; then
		#echo; cat /mnt/etc/fstab
		echo; echo "bash for corrections... (ctrl+D or exit)"; echo
		bash
	fi
}

function MyDebianChroot() {
# Mounte notwendige Dateisysteme
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --rbind /dev /mnt/dev

# treiber von live cd kopieren
cp -r /lib/firmware /mnt/lib/firmware
#cp -r /lib/modules /mnt/lib/modules
# Chroote in das Debian-System
LANG=$LANG chroot /mnt /bin/bash <<CHROOT_SCRIPT
# Innerhalb des Chroots
# Lang & keyboard
echo "${LANG} UTF-8" >> /etc/locale.gen
# language multivar not compatible
# echo "LANG=${LANG}" >/etc/default/locale

cat <<EOT >/etc/default/keyboard
XKBMODEL="pc105"
XKBLAYOUT="ch"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
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
deb http://archive.ubuntu.com/ubuntu/ ${myDist} main restricted universe
deb http://security.ubuntu.com/ubuntu/ ${myDist}-security main restricted universe
deb http://archive.ubuntu.com/ubuntu/ ${myDist}-updates main restricted universe
EOT

# Aktualisiere apt
apt update >/dev/null
apt install -yqq linux-firmware >/dev/null

# add a user +sudo and a pw
myUserpw='$6$Mex8UsSXMCxrMB0e$tvbg.anIuLPNQBH3j0.yvLaa.s4yF9k3jVzB4rekcFk/GIGHvl.kPsqkC57Etqhnmf2g2KCi5hnz4QKxp5hUR0'
adduser --disabled-password --gecos "user (sudo)" $myUsername
usermod -aG sudo $myUsername
cat <<EOP | passwd $myUsername
$myUsername
$myUsername
EOP
# echo "${myUsername}:${myUserpw}" | chpasswd -e
usermod -aG adm,audio,cdrom,video,netdev,plugdev,sudo,users $myUsername

# users
myUserpw='$6$Q4mEIbASFCAmwxCZ$Uy5.P.CnxwfXYBrcAvo.xjGf6EJi3py.FTCFHfWcnpQSVS5GYm6E4aTh6/Sh.y1OSZ/6HxzH.cnDyOSPWzh/60'
useradd -m -p $myUserpw -s /bin/bash -c "boss (sudo)" "boss" -G adm,audio,cdrom,video,netdev,plugdev,sudo,users

myUserpw='$6$cs1uZZfrRhHzgC4U$lE4/hsyd.blFC2qaNxvHDDOKdD0QgFe3FNacx62iq9Uw40XMLuRZgvGh3IENM3rznmKPL0yqqV5xtjyhIFWxR.'
useradd -m -p $myUserpw -s /bin/bash -c "mitarbeiter" "mitarbeiter" -G cdrom,plugdev,users

# must have
apt install -yqq nano sudo ssh curl locales console-setup >/dev/null
unlink /etc/localtime; ln -s /usr/share/zoneinfo/Europe/Zurich /etc/localtime
#locale-gen ${LANG}
#update-locale LANG=${LANG}
#LANGUAGE="${LANGUAGE}"

#grub & related
apt install -yqq grub-efi-amd64-bin grub-common linux-image-generic >/dev/null
grub-install
update-grub

# Ende des Chroots
CHROOT_SCRIPT

# lokales file - update vom Netz soll ueberschreiben
if [ -f $fname ]; then
  cp -fv "${fname}" /mnt/usr/local/bin/
fi

apt install -yq curl
gitUrl="https://raw.githubusercontent.com/dneuhaus76/public/refs/heads/main/postinstall_kde.sh"
if curl --output /dev/null --silent --fail -r 0-0 "${gitUrl}"; then
  curl -o /mnt/usr/local/bin/${fname} --silent ${gitUrl}
fi

#MyStage 2 Chroot
#LANG=$LANG chroot /mnt /bin/bash /usr/local/bin/${fname}
LANG=$LANG chroot /mnt /bin/bash <<CHROOT_SCRIPT

#Einfach grafische KDE-Oberflaeche
apt install -yqq kde-plasma-desktop sddm sddm-theme-breeze kwin-x11 plasma-nm konsole network-manager systemsettings dolphin ark snapd >/dev/null

#snap vorbereiten
snap install core snapd
systemctl restart snapd

#starte postinstall
bash /usr/local/bin/${fname}

# Weitere Anpassungen oder Installationen können hier erfolgen

#Checks
#echo; cat /etc/apt/sources.list
echo
echo "final chroot checks"
echo

# Ende des Chroots
CHROOT_SCRIPT

	# Bereinige und unmounte
	umount -R /mnt
}

# Main
NewDiskSchema
NewOSInstall
MyDebianChroot

# Cleanup
umount -Rl /mnt

#Check
#read -p "poweroff? (y/n): " continue_response
#if [ $continue_response == "y" ]; then
	poweroff -p
#fi
