#!/bin/bash

# ----------------------------------------
# Define Variables
# ----------------------------------------

MYUSERNM="Araf"
# use all lowercase letters only

MYUSRPASSWD="1122"
# Pick a password of your choice

RTPASSWD="1122"
# Pick a root password

MYHOSTNM="sk"
# Pick a hostname for the machine

WORKDIR="/home/arafsk/DATA/iso-make"

OUTDIR="/home/arafsk/DATA/iso-make/out"

# ----------------------------------------
# Functions
# ----------------------------------------

# Test for root user
rootuser () {
  if [[ "$EUID" = 0 ]]; then
    continue
  else
    echo "Please Run As Root"
    sleep 2
    exit
  fi
}

# Display line error
handlerror () {
clear
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR
}

# Clean up working directories
cleanup () {
rm -rf "${WORKDIR}/build" "${OUTDIR}" ./releng
sleep 2
}

# Requirements and preparation
prepreqs () {
pacman -S --needed --noconfirm archiso mkinitcpio-archiso
}

# Copy releng to working directory
cpreleng () {
cp -r /usr/share/archiso/configs/releng/ ./releng
rm ./releng/airootfs/etc/motd
rm ./releng/airootfs/etc/mkinitcpio.d/linux.preset
rm ./releng/airootfs/etc/ssh/sshd_config.d/10-archiso.conf
rm -r ./releng/grub
rm -r ./releng/efiboot
rm -r ./releng/syslinux
rm -r ./releng/airootfs/etc/mkinitcpio.conf.d
}

# Copy ezrepo to opt
cpezrepo () {
cp -r ./airootfs/opt/arafsk_repo/ /opt/
}

# Remove ezrepo from opt
rmezrepo () {
rm -r /opt/arafsk_repo
}

# Remove auto-login, cloud-init, hyper-v, iwd, sshd, & vmware services
rmunitsd () {
rm -r ./releng/airootfs/etc/systemd/system/cloud-init.target.wants
rm -r ./releng/airootfs/etc/systemd/system/getty@tty1.service.d
rm ./releng/airootfs/etc/systemd/system/multi-user.target.wants/hv_fcopy_daemon.service
rm ./releng/airootfs/etc/systemd/system/multi-user.target.wants/hv_kvp_daemon.service
rm ./releng/airootfs/etc/systemd/system/multi-user.target.wants/hv_vss_daemon.service
rm ./releng/airootfs/etc/systemd/system/multi-user.target.wants/vmware-vmblock-fuse.service
rm ./releng/airootfs/etc/systemd/system/multi-user.target.wants/vmtoolsd.service
rm ./releng/airootfs/etc/systemd/system/multi-user.target.wants/sshd.service
rm ./releng/airootfs/etc/systemd/system/multi-user.target.wants/iwd.service
}

# Add cups, display manager, haveged, NetworkManager, & reflector systemd links
addnmlinks () {
mkdir -p ./releng/airootfs/etc/systemd/system/network-online.target.wants
mkdir -p ./releng/airootfs/etc/systemd/system/multi-user.target.wants
mkdir -p ./releng/airootfs/etc/systemd/system/printer.target.wants
mkdir -p ./releng/airootfs/etc/systemd/system/sockets.target.wants
mkdir -p ./releng/airootfs/etc/systemd/system/timers.target.wants
mkdir -p ./releng/airootfs/etc/systemd/system/sysinit.target.wants
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service ./releng/airootfs/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service ./releng/airootfs/etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service
ln -sf /usr/lib/systemd/system/NetworkManager.service ./releng/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service
ln -sf /usr/lib/systemd/system/reflector.service ./releng/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service
ln -sf /usr/lib/systemd/system/haveged.service ./releng/airootfs/etc/systemd/system/sysinit.target.wants/haveged.service
ln -sf /usr/lib/systemd/system/cups.service ./releng/airootfs/etc/systemd/system/printer.target.wants/cups.service
ln -sf /usr/lib/systemd/system/cups.socket ./releng/airootfs/etc/systemd/system/sockets.target.wants/cups.socket
ln -sf /usr/lib/systemd/system/cups.path ./releng/airootfs/etc/systemd/system/multi-user.target.wants/cups.path
ln -sf /usr/lib/systemd/system/lightdm.service ./releng/airootfs/etc/systemd/system/display-manager.service
}

# Copy files to customize the ISO
cpmyfiles () {
cp pacman.conf ./releng/
cp profiledef.sh ./releng/
cp packages.x86_64 ./releng/

cp -r grub/ ./releng/
cp -r efiboot/ ./releng/
cp -r syslinux/ ./releng/
cp -r airootfs/etc/ ./releng/airootfs/
cp -r airootfs/opt/ ./releng/airootfs/
cp -r airootfs/usr/ ./releng/airootfs/
cp -r airootfs/root/ ./releng/airootfs/
}

# Set hostname
sethostname () {
echo "${MYHOSTNM}" > ./releng/airootfs/etc/hostname
}

# Create passwd file
crtpasswd () {
echo "root:x:0:0:root:/root:/usr/bin/bash
"${MYUSERNM}":x:1010:1010::/home/"${MYUSERNM}":/usr/bin/bash" > ./releng/airootfs/etc/passwd
}

# Create group file
crtgroup () {
echo "root:x:0:root
sys:x:3:"${MYUSERNM}"
adm:x:4:"${MYUSERNM}"
wheel:x:10:"${MYUSERNM}"
log:x:18:"${MYUSERNM}"
network:x:90:"${MYUSERNM}"
floppy:x:94:"${MYUSERNM}"
scanner:x:96:"${MYUSERNM}"
power:x:98:"${MYUSERNM}"
uucp:x:810:"${MYUSERNM}"
audio:x:820:"${MYUSERNM}"
lp:x:830:"${MYUSERNM}"
rfkill:x:840:"${MYUSERNM}"
video:x:850:"${MYUSERNM}"
storage:x:860:"${MYUSERNM}"
optical:x:870:"${MYUSERNM}"
sambashare:x:880:"${MYUSERNM}"
users:x:985:"${MYUSERNM}"
"${MYUSERNM}":x:1010:" > ./releng/airootfs/etc/group
}

# Create shadow file
crtshadow () {
user_hash=$(openssl passwd -6 "${MYUSRPASSWD}")
root_hash=$(openssl passwd -6 "${RTPASSWD}")
echo "root:"${root_hash}":14871::::::
"${MYUSERNM}":"${user_hash}":14871::::::" > ./releng/airootfs/etc/shadow
}

# create gshadow file
crtgshadow () {
echo "root:!*::root
sys:!*::"${MYUSERNM}"
adm:!*::"${MYUSERNM}"
wheel:!*::"${MYUSERNM}"
log:!*::"${MYUSERNM}"
network:!*::"${MYUSERNM}"
floppy:!*::"${MYUSERNM}"
scanner:!*::"${MYUSERNM}"
power:!*::"${MYUSERNM}"
uucp:!*::"${MYUSERNM}"
audio:!*::"${MYUSERNM}"
lp:!*::"${MYUSERNM}"
rfkill:!*::"${MYUSERNM}"
video:!*::"${MYUSERNM}"
storage:!*::"${MYUSERNM}"
optical:!*::"${MYUSERNM}"
sambashare:!*::"${MYUSERNM}"
"${MYUSERNM}":!*::" > ./releng/airootfs/etc/gshadow
}

# Start mkarchiso
runmkarchiso () {
    echo "[*]" "Starting ISO build process..."
    mkdir -p "${WORKDIR}"
    mkdir -p "${OUTDIR}"
    mkarchiso -v -w "${WORKDIR}/build" -o "${OUTDIR}" ./releng
}

cppkglist() {
echo "✓ Package list copied"
cp "${WORKDIR}/build/iso/arch/pkglist.x86_64.txt" "${OUTDIR}/"
}

# ----------------------------------------
# Run Functions
# ----------------------------------------

rootuser
handlerror
prepreqs
cleanup
cpreleng
addnmlinks
cpezrepo
rmunitsd
cpmyfiles
sethostname
crtpasswd
crtgroup
crtshadow
crtgshadow
runmkarchiso
cppkglist
rmezrepo
#
# END
#
