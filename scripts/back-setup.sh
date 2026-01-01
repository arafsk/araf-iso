#!/bin/bash
#
# Araf OS ISO Builder
# Advanced Arch Linux ISO creation script
# Author: Arafsk
# Version: 2.0
#

# ----------------------------------------
# Define Variables
# ----------------------------------------

MYUSERNM="liveuser"
# use all lowercase letters only

MYUSRPASSWD="1122"
# Pick a password of your choice

RTPASSWD="1122"
# Pick a root password

MYHOSTNM="Araf_OS"
# Pick a hostname for the machine
HOME="/home/munna"
BUILD_DIR=$HOME"/DATA/iso-build"
OUT_DIR=$HOME"/DATA/iso-out"
RELENG_DIR=$HOME"/DATA/releng"
ARCHISO_DIR=$HOME"/Desktop/athena/archiso"

# ==========================================
# COLOR CODES
# ==========================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color
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

# Requirements and preparation
prepreqs () {
    echo "Checking dependencies..."
    
    local dependencies=(
        archiso
        openssl
        mkinitcpio-archiso
        squashfs-tools
        dosfstools
        libisoburn
        xorriso
        git
        wget
        curl
        jq
    )
    
    local missing=()
    
    for dep in "${dependencies[@]}"; do
        if ! pacman -Qi "$dep" &>/dev/null && ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warning "Missing dependencies: ${missing[*]}"
        read -p "Install missing dependencies? [Y/n]: " -r
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            pacman -S --needed --noconfirm "${missing[@]}"
            echo "Dependencies installed"
        else
            log_error "Required dependencies missing"
            exit 1
        fi
    else
        echo "All dependencies satisfied"
    fi
}

# Copy releng to working directory
cpreleng () {
    cp -r /usr/share/archiso/configs/releng "$RELENG_DIR"
    
    # Clean up default files
    local files_to_remove=(
        "$RELENG_DIR/airootfs/etc/motd"
        "$RELENG_DIR/airootfs/etc/mkinitcpio.d/linux.preset"
        "$RELENG_DIR/airootfs/etc/ssh/sshd_config.d/10-archiso.conf"
    )
    
    for file in "${files_to_remove[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
    
    # Remove default boot directories
    rm -rf "$RELENG_DIR"/{grub,efiboot,syslinux} 2>/dev/null || true
    rm -rf "$RELENG_DIR/airootfs/etc/mkinitcpio.conf.d/" 2>/dev/null || true
}

#Copy ezrepo to opt
cpezrepo () {
    cp -r "$RELENG_DIR/airootfs/opt/personal_repo/" "/opt/" 2>/dev/null || true
}

# Copy files to customize the ISO
cpmyfiles () {
    # Copy main configuration files
    cp -v "$ARCHISO_DIR/pacman.conf" "$RELENG_DIR/"
    cp -v "$ARCHISO_DIR/profiledef.sh" "$RELENG_DIR/"
    cp -v "$ARCHISO_DIR/packages.x86_64" "$RELENG_DIR/"
    
    # Copy boot configuration
    cp -rv "$ARCHISO_DIR/grub/" "$RELENG_DIR/"
    cp -rv "$ARCHISO_DIR/efiboot/" "$RELENG_DIR/"
    cp -rv "$ARCHISO_DIR/syslinux/" "$RELENG_DIR/"
    
    # Copy custom files from airootfs
    cp -rv "$ARCHISO_DIR/airootfs/etc/" "$RELENG_DIR/airootfs/"
    cp -rv "$ARCHISO_DIR/airootfs/opt/" "$RELENG_DIR/airootfs/"
    cp -rv "$ARCHISO_DIR/airootfs/usr/" "$RELENG_DIR/airootfs/"
    cp -rv "$ARCHISO_DIR/airootfs/root/" "$RELENG_DIR/airootfs/"
}

setup_users() {
    echo "Setting up users and groups..."
    
    # Create passwd file
    cat > "$RELENG_DIR/airootfs/etc/passwd" << EOF
root:x:0:0:root:/root:/usr/bin/bash
${MYUSERNM}:x:1000:1000::/home/${MYUSERNM}:/usr/bin/bash
EOF
    
    # Create group file
    cat > "$RELENG_DIR/airootfs/etc/group" << EOF
root:x:0:root
sys:x:3:${MYUSERNM}
adm:x:4:${MYUSERNM}
wheel:x:10:${MYUSERNM}
log:x:18:${MYUSERNM}
network:x:90:${MYUSERNM}
floppy:x:94:${MYUSERNM}
scanner:x:96:${MYUSERNM}
power:x:98:${MYUSERNM}
uucp:x:810:${MYUSERNM}
audio:x:820:${MYUSERNM}
lp:x:830:${MYUSERNM}
rfkill:x:840:${MYUSERNM}
video:x:850:${MYUSERNM}
storage:x:860:${MYUSERNM}
optical:x:870:${MYUSERNM}
sambashare:x:880:${MYUSERNM}
users:x:985:${MYUSERNM}
${MYUSERNM}:x:1000:
EOF
    
    # Generate password hashes
    local user_hash=$(openssl passwd -6 "${MYUSRPASSWD:-1122}" 2>/dev/null || echo '$6$rounds=656000$5B.ZHtp8W9P$')
    local root_hash=$(openssl passwd -6 "${RTPASSWD:-1122}" 2>/dev/null || echo '$6$rounds=656000$5B.ZHtp8W9P$')
    
    # Create shadow file
    cat > "$RELENG_DIR/airootfs/etc/shadow" << EOF
root:${root_hash}:14871::::::
${MYUSERNM}:${user_hash}:14871::::::
EOF
    
    # Create gshadow file
    cat > "$RELENG_DIR/airootfs/etc/gshadow" << EOF
root:!*::root
sys:!*::${MYUSERNM}
adm:!*::${MYUSERNM}
wheel:!*::${MYUSERNM}
log:!*::${MYUSERNM}
network:!*::${MYUSERNM}
floppy:!*::${MYUSERNM}
scanner:!*::${MYUSERNM}
power:!*::${MYUSERNM}
uucp:!*::${MYUSERNM}
audio:!*::${MYUSERNM}
lp:!*::${MYUSERNM}
rfkill:!*::${MYUSERNM}
video:!*::${MYUSERNM}
storage:!*::${MYUSERNM}
optical:!*::${MYUSERNM}
sambashare:!*::${MYUSERNM}
${MYUSERNM}:!*::
EOF
    
    # Set hostname
    echo "${MYHOSTNM}" > "$RELENG_DIR/airootfs/etc/hostname"
    
    # Update hosts file
    cat > "$RELENG_DIR/airootfs/etc/hosts" << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${MYHOSTNM}.localdomain ${MYHOSTNM}
EOF
    
    echo "Users and groups configured"
}

setup_systemd_services() {
    echo "Configuring systemd services..."
    
    local systemd_base="$RELENG_DIR/airootfs/etc/systemd/system"
    
    # Create necessary directories
    mkdir -p "$systemd_base"/{network-online.target.wants,multi-user.target.wants,printer.target.wants,sockets.target.wants,timers.target.wants,sysinit.target.wants}
    
    # Remove unwanted services
    local services_to_remove=(
        "$systemd_base/cloud-init.target.wants"
        "$systemd_base/getty@tty1.service.d"
        "$systemd_base/multi-user.target.wants/hv_fcopy_daemon.service"
        "$systemd_base/multi-user.target.wants/hv_kvp_daemon.service"
        "$systemd_base/multi-user.target.wants/hv_vss_daemon.service"
        "$systemd_base/multi-user.target.wants/vmware-vmblock-fuse.service"
        "$systemd_base/multi-user.target.wants/vmtoolsd.service"
        "$systemd_base/multi-user.target.wants/sshd.service"
        "$systemd_base/multi-user.target.wants/iwd.service"
    )
    
    for service in "${services_to_remove[@]}"; do
        [[ -e "$service" ]] && rm -rf "$service"
    done
    
    # Create service symlinks
    local services=(
        "NetworkManager-wait-online.service:network-online.target.wants"
        "NetworkManager-dispatcher.service:dbus-org.freedesktop.nm-dispatcher.service"
        "NetworkManager.service:multi-user.target.wants"
        "reflector.service:multi-user.target.wants"
        "haveged.service:sysinit.target.wants"
        "cups.service:printer.target.wants"
        "cups.socket:sockets.target.wants"
        "cups.path:multi-user.target.wants"
        "lightdm.service:display-manager.service"
    )
    
    for service_link in "${services[@]}"; do
        IFS=':' read -r service target <<< "$service_link"
        ln -sf "/usr/lib/systemd/system/$service" "$systemd_base/$target" 2>/dev/null || true
    done
    
    echo "Systemd services configured"
}

build_iso() {
    echo "Start Building ISO image..."
    mkarchiso -v -w "$BUILD_DIR" -o "$OUT_DIR" "$RELENG_DIR"
    
    # Check if build was successful
    if [[ ! -f "$OUT_DIR"/*.iso ]]; then
        log_error "ISO build failed"
        exit 1
    fi
    
    echo "ISO build completed successfully"
}

verify_iso() {
    if [[ "$SKIP_VERIFY" == true ]]; then
        log_info "Skipping ISO verification"
        return 0
    fi
    
    echo "Verifying ISO file..."
    
    local iso_file=$(find "$OUT_DIR" -name "*.iso" -type f | head -n1)
    
    if [[ -z "$iso_file" ]]; then
        log_error "No ISO file found"
        return 1
    fi
    
    local iso_size=$(du -h "$iso_file" | cut -f1)
    log_info "ISO File: $(basename "$iso_file")"
    log_info "ISO Size: $iso_size"
    
    # Generate checksums
    cd "$OUT_DIR"
    local base_name=$(basename "$iso_file")
    
    log_info "Generating SHA256 checksum..."
    sha256sum "$base_name" > "${base_name}.sha256"
    
    log_info "Generating MD5 checksum..."
    md5sum "$base_name" > "${base_name}.md5"
    
    # Verify checksums
    if sha256sum -c "${base_name}.sha256" &>/dev/null; then
        echo "SHA256 checksum verified"
    else
        log_error "SHA256 checksum verification failed"
        return 1
    fi
    
    if md5sum -c "${base_name}.md5" &>/dev/null; then
        echo "MD5 checksum verified"
    else
        log_error "MD5 checksum verification failed"
        return 1
    fi
    
    # Test ISO reading
    if command -v isoinfo &>/dev/null; then
        if isoinfo -d -i "$iso_file" &>/dev/null; then
            echo "ISO structure validated"
        else
            log_warning "ISO structure validation failed"
        fi
    fi
    
    echo "ISO verification completed"
}

sign_iso() {
    if [[ "$SIGN_ISO" != true ]]; then
        return 0
    fi
    
    echo "Signing ISO file..."
    
    local iso_file=$(find "$OUT_DIR" -name "*.iso" -type f | head -n1)
    
    if [[ -z "$iso_file" ]]; then
        log_error "No ISO file to sign"
        return 1
    fi
    
    local key_to_use="${GPG_KEY:-}"
    
    if [[ -z "$key_to_use" ]]; then
        # Try to find a suitable GPG key
        local available_keys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep sec | awk '{print $2}' | cut -d'/' -f2)
        
        if [[ -n "$available_keys" ]]; then
            key_to_use=$(echo "$available_keys" | head -n1)
            log_info "Using GPG key: $key_to_use"
        else
            log_warning "No GPG key found, skipping signing"
            return 0
        fi
    fi
    
    # Sign the ISO
    if gpg --detach-sign --armor --default-key "$key_to_use" "$iso_file" 2>/dev/null; then
        echo "ISO signed successfully"
    else
        log_warning "Failed to sign ISO"
    fi
}

# Remove ezrepo from opt
rmezrepo () {
    rm -rf /opt/personal_repo
}

# ----------------------------------------
# Run Functions
# ----------------------------------------

rootuser
handlerror
prepreqs
cpreleng
cpezrepo
cpmyfiles
setup_users
setup_systemd_services
build_iso
verify_iso
sign_iso
rmezrepo
#runmkarchiso
#cppkglist
#rmezrepo
#
# END
#
