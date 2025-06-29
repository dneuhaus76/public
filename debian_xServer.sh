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
export DEBIAN_FRONTEND=noninteractive

# disable ipv6 during this installation
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# check current mode 
echo;[ -d /sys/firmware/efi ] && echo "EFI boot on HDD" || echo "Legacy boot on HDD"
echo; lsblk -l
echo "Enter Device name (/dev/x)"
read -r myDev
#echo "Enter Distribution name (default is ${myDist})"
#read -r myDist

export myDist="${myDist:-bookworm}"
export myDev="${myDev:-/dev/sda}"
export myPartPrefix="$myDev"

# Check if the device is an eMMC or a hard disk
if [[ $myDev == *mmcblk* ]]; then
    drive_type="eMMC"
    myPartPrefix="${myDev}p"
else
    drive_type="HD"
fi

# Print the drive type
echo "Drive $myDev is a $drive_type."

echo; lsblk "${myDev}" -l
echo; echo "bash before partitions... (ctrl+D or exit)"; echo
bash

function NewDiskSchema() {
    # Unmount partitions
    #umount -l "${myPartPrefix}1"
    #umount -l "${myPartPrefix}2"
    umount -l ${myPartPrefix}* 2
	sleep 2s
	
    # Cleanup bootsector
    dd if=/dev/zero of="${myDev}" bs=512 count=1

    # Create new partition schema
    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOT | fdisk "${myDev}"
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

    # Format partitions
    sleep 2s
    mkfs.vfat "${myPartPrefix}1"
    mkfs.ext4 -F "${myPartPrefix}2"

    # Mount partitions for installation
    mount "${myPartPrefix}2" /mnt
    sleep 2s
    mkdir -p /mnt/boot/efi
    mount "${myPartPrefix}1" /mnt/boot/efi

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
    apt install -yqq debian-archive-keyring debian-keyring
    apt install -yqq debootstrap
	debootstrap --no-check-gpg --arch=amd64 ${myDist} /mnt ${mySite}

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
# Mounte notwendige Dateisysteme
mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --rbind /dev /mnt/dev

# treiber von live cd kopieren
cp -r /lib/firmware /mnt/lib/firmware
cp -r /lib/modules /mnt/lib/modules
#mount --rbind /lib/firmware /mnt/lib/firmware
#mount --rbind /lib/modules /mnt/lib/modules
cp -v $SCRIPT_DIR/myPreferencesLXQT.sh /mnt/

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

# Aktualisiere apt
apt update
apt install -yqq firmware-linux firmware-linux-free firmware-linux-nonfree firmware-misc-nonfree

# add a user +sudo and a pw
adduser --disabled-password --gecos "" $myUsername
usermod -aG sudo $myUsername
cat <<EOP | passwd $myUsername
$myUsername
$myUsername
EOP
usermod -aG adm,audio,cdrom,video,netdev,plugdev,users $myUsername

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

# Ende des Chroots
CHROOT_SCRIPT

#MyStage 2 Chroot
#Check
LANG=$LANG chroot /mnt /bin/bash <<CHROOT_SCRIPT
# Installiere meine Applikationen - fix für connman
apt install -yqq xserver-xorg-core lightdm lightdm-settings slick-greeter lxqt xrdp chromium thunderbird libwebkit2gtk-4.0-37 
apt install -yqq --no-install-recommends xserver-xorg network-manager-gnome
apt purge -yqq connman
apt install -yqq

# Weitere Anpassungen oder Installationen können hier erfolgen
adduser xrdp ssl-cert
cat <<EOT >>/etc/sudoers.d/shutdown
%sudo ALL=(ALL) NOPASSWD: /sbin/shutdown
%sudo ALL=(ALL) NOPASSWD: /sbin/reboot
EOT

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

bash /myPreferencesLXQT.sh

#Checks
echo; cat /etc/apt/sources.list
echo
echo "final chroot checks"
echo

# Ende des Chroots
CHROOT_SCRIPT

	# Bereinige und unmounte
	umount -l /mnt/sys
	umount -l /mnt/proc
	umount -l /mnt/dev
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


