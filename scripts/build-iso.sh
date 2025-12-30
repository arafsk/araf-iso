#!/bin/bash
#
# Araf OS ISO Builder
# Advanced Arch Linux ISO creation script
# Author: Arafsk
# Version: 2.0
#

# ==========================================
# STRICT MODE & INITIAL SETUP
# ==========================================
set -euo pipefail
IFS=$'\n\t'

# ==========================================
# CONFIGURATION
# ==========================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly ARCHISO_DIR="/home/munna/DATA/iso-make/arafos-iso/archiso"
readonly BASE_DIR="/home/munna/DATA/iso-make"
readonly BUILD_DIR="${BASE_DIR}/build"
readonly OUT_DIR="${BASE_DIR}/out"
readonly RELENG_DIR="${BASE_DIR}/releng"
readonly BACKUP_DIR="${BASE_DIR}/backups"
readonly LOG_FILE="${BASE_DIR}/build_log_$(date +%Y%m%d_%H%M%S).log"

# ----------------------------------------
# User Configuration (can be overridden by arguments)
# ----------------------------------------
MYUSERNM="liveuser"
MYUSRPASSWD="1122"
RTPASSWD="1122"
MYHOSTNM="Araf_OS"

# ==========================================
# COLOR CODES
# ==========================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color


# ==========================================
# LOGGING FUNCTIONS
# ==========================================
log() {
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "\n${CYAN}▶${NC} $*" | tee -a "$LOG_FILE"
}

# ==========================================
# UTILITY FUNCTIONS
# ==========================================
show_progress() {
    local current=$1
    local total=$2
    local task=$3
    local percent=$((current * 100 / total))
    printf "\r[%3d%%] [%2d/%2d] %s..." "$percent" "$current" "$total" "$task"
}

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════╗
║                                           ║
║         Araf OS ISO Builder v2.0          ║
║     Advanced Arch Linux ISO Creator       ║
║                                           ║
╚═══════════════════════════════════════════╝
EOF
}

usage() {
    cat << EOF

Usage: $0 [OPTIONS]


Options:
    -u, --user USERNAME      Set username (default: liveuser)
    -h, --hostname HOSTNAME  Set hostname (default: Araf_OS)
    -c, --clean             Clean previous build before starting
    -i, --interactive       Run in interactive mode
    -b, --backup            Backup previous ISO before building
    -v, --verbose           Enable verbose output
    -s, --skip-verify       Skip ISO verification
    --help                  Show this help message

Environment Variables:
    MYUSRPASSWD             User password (prompted if not set)
    RTPASSWD                Root password (prompted if not set)

Examples:
    $0 -u myuser -h MyOS --clean
    $0 --interactive --backup
    MYUSRPASSWD=pass123 RTPASSWD=root123 $0 -c

EOF
}

# ----------------------------------------
# Functions
# ----------------------------------------
# Test for root user
rootuser() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0 $*"
        exit 1
    fi
}

# Display line error
handlerror() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Build failed with exit code: $exit_code"
        log_info "Check log file: $LOG_FILE"
        
        # Clean up temporary files
        [[ -d "/opt/arafsk_repo" ]] && rm -rf /opt/arafsk_repo
        
        exit $exit_code
    fi
}

trap cleanup_on_error ERR

# ==========================================
# BUILD FUNCTIONS
# ==========================================
backup_previous_iso() {
    log_step "Checking for previous ISO..."
    
    local iso_files=("${OUT_DIR}"/*.iso)
    if [[ -f "${iso_files}" ]]; then
        local backup_subdir="${BACKUP_DIR}/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_subdir"
        
        mv "${OUT_DIR}"/*.iso "$backup_subdir/" 2>/dev/null || true
        mv "${OUT_DIR}"/*.sha256 "$backup_subdir/" 2>/dev/null || true
        mv "${OUT_DIR}"/*.md5 "$backup_subdir/" 2>/dev/null || true
        
        log_success "Previous ISO backed up to: $backup_subdir"
    else
        log_info "No previous ISO found"
    fi
}

prepreqs() {
    log_step "Installing prerequisites..."
    pacman -S --needed --noconfirm archiso openssl mkinitcpio-archiso
    log_success "Prerequisites installed"
}

cpreleng() {
    log_step "Copying releng configuration..."
    
    cp -r /usr/share/archiso/configs/releng "$RELENG_DIR"
    
    # Remove default files
    rm -f "$RELENG_DIR/airootfs/etc/motd"
    rm -f "$RELENG_DIR/airootfs/etc/mkinitcpio.d/linux.preset"
    rm -f "$RELENG_DIR/airootfs/etc/ssh/sshd_config.d/10-archiso.conf"
    
    # Remove default boot loaders
    rm -rf "$RELENG_DIR"/{grub,efiboot,syslinux}
    rm -rf "$RELENG_DIR/airootfs/etc/mkinitcpio.conf.d/"
    
    log_success "Releng configuration copied"
}

cpezrepo() {
    log_step "Copying custom repository..."
    
    if [[ -d "$ARCHISO_DIR/airootfs/opt/arafsk_repo" ]]; then
        cp -r "$ARCHISO_DIR/airootfs/opt/arafsk_repo/" /opt/
        log_success "Custom repository copied to /opt"
    else
        log_warning "Custom repository not found, skipping..."
    fi
}

rmunitsd() {
    log_step "Removing unwanted systemd services..."
    
    local services_to_remove=(
        "$RELENG_DIR/airootfs/etc/systemd/system/cloud-init.target.wants"
        "$RELENG_DIR/airootfs/etc/systemd/system/getty@tty1.service.d"
        "$RELENG_DIR/airootfs/etc/systemd/system/multi-user.target.wants/hv_fcopy_daemon.service"
        "$RELENG_DIR/airootfs/etc/systemd/system/multi-user.target.wants/hv_kvp_daemon.service"
        "$RELENG_DIR/airootfs/etc/systemd/system/multi-user.target.wants/hv_vss_daemon.service"
        "$RELENG_DIR/airootfs/etc/systemd/system/multi-user.target.wants/vmware-vmblock-fuse.service"
        "$RELENG_DIR/airootfs/etc/systemd/system/multi-user.target.wants/vmtoolsd.service"
        "$RELENG_DIR/airootfs/etc/systemd/system/multi-user.target.wants/sshd.service"
        "$RELENG_DIR/airootfs/etc/systemd/system/multi-user.target.wants/iwd.service"
    )
    
    for service in "${services_to_remove[@]}"; do
        [[ -e "$service" ]] && rm -rf "$service"
    done
    
    log_success "Unwanted services removed"
}

addnmlinks() {
    log_step "Adding custom systemd service links..."
    
    local systemd_base="$RELENG_DIR/airootfs/etc/systemd/system"
    
    # Create target directories
    mkdir -p "$systemd_base"/{network-online.target.wants,multi-user.target.wants,printer.target.wants,sockets.target.wants,timers.target.wants,sysinit.target.wants}
    
    # NetworkManager links
    ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service \
        "$systemd_base/network-online.target.wants/NetworkManager-wait-online.service"
    
    ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service \
        "$systemd_base/dbus-org.freedesktop.nm-dispatcher.service"
    
    ln -sf /usr/lib/systemd/system/NetworkManager.service \
        "$systemd_base/multi-user.target.wants/NetworkManager.service"
    
    # Other service links
    ln -sf /usr/lib/systemd/system/reflector.service \
        "$systemd_base/multi-user.target.wants/reflector.service"
    
    ln -sf /usr/lib/systemd/system/haveged.service \
        "$systemd_base/sysinit.target.wants/haveged.service"
    
    # CUPS links
    ln -sf /usr/lib/systemd/system/cups.service \
        "$systemd_base/printer.target.wants/cups.service"
    
    ln -sf /usr/lib/systemd/system/cups.socket \
        "$systemd_base/sockets.target.wants/cups.socket"
    
    ln -sf /usr/lib/systemd/system/cups.path \
        "$systemd_base/multi-user.target.wants/cups.path"
    
    # Display manager link
    ln -sf /usr/lib/systemd/system/lightdm.service \
        "$systemd_base/display-manager.service"
    
    log_success "Service links created"
}

cpmyfiles() {
    log_step "Copying custom files to releng..."
    
    # Copy main configuration files
    cp "$ARCHISO_DIR/pacman.conf" "$RELENG_DIR/"
    cp "$ARCHISO_DIR/profiledef.sh" "$RELENG_DIR/"
    cp "$ARCHISO_DIR/packages.x86_64" "$RELENG_DIR/"
    
    # Copy boot configuration
    cp -r "$ARCHISO_DIR/grub/" "$RELENG_DIR/"
    cp -r "$ARCHISO_DIR/efiboot/" "$RELENG_DIR/"
    cp -r "$ARCHISO_DIR/syslinux/" "$RELENG_DIR/"
    
    # Copy custom files from airootfs
    cp -r "$ARCHISO_DIR/airootfs/etc/" "$RELENG_DIR/airootfs/"
    cp -r "$ARCHISO_DIR/airootfs/opt/" "$RELENG_DIR/airootfs/"
    cp -r "$ARCHISO_DIR/airootfs/usr/" "$RELENG_DIR/airootfs/"
    cp -r "$ARCHISO_DIR/airootfs/root/" "$RELENG_DIR/airootfs/"
    
    log_success "Custom files copied"
}

sethostname() {
    log_step "Setting hostname..."
    echo "${MYHOSTNM}" > "$RELENG_DIR/airootfs/etc/hostname"
    log_success "Hostname set to: $MYHOSTNM"
}

crtpasswd() {
    log_step "Creating passwd file..."
    cat > "$RELENG_DIR/airootfs/etc/passwd" << EOF
root:x:0:0:root:/root:/usr/bin/bash
${MYUSERNM}:x:1010:1010::/home/${MYUSERNM}:/usr/bin/bash
EOF
    log_success "Passwd file created"
}

crtgroup() {
    log_step "Creating group file..."
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
${MYUSERNM}:x:1010:
EOF
    log_success "Group file created"
}

crtshadow() {
    log_step "Creating shadow file..."
    user_hash=$(openssl passwd -6 "${MYUSRPASSWD}")
    root_hash=$(openssl passwd -6 "${RTPASSWD}")
    
    cat > "$RELENG_DIR/airootfs/etc/shadow" << EOF
root:${root_hash}:14871::::::
${MYUSERNM}:${user_hash}:14871::::::
EOF
    
    log_success "Shadow file created"
}

crtgshadow() {
    log_step "Creating gshadow file..."
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
    
    log_success "Gshadow file created"
}

runmkarchiso() {
    log_step "Starting ISO build process..."
    mkarchiso -v -w "$BUILD_DIR" -o "$OUT_DIR" "$RELENG_DIR"
    
    # Check if build was successful
    if [[ ! -f "$OUT_DIR"/*.iso ]]; then
        log_error "ISO build failed"
        exit 1
    fi
    
    log_success "ISO build completed successfully"
}

verify_iso() {
    log_step "Verifying ISO file..."
    
    local iso_file=$(find "$OUT_DIR" -name "*.iso" -type f | head -n1)
    
    if [[ -z "$iso_file" ]]; then
        log_error "No ISO file found in output directory"
        return 1
    fi
    
    # Generate checksums
    cd "$OUT_DIR"
    sha256sum "$(basename "$iso_file")" > "$(basename "$iso_file").sha256"
    md5sum "$(basename "$iso_file")" > "$(basename "$iso_file").md5"
    
    log_success "ISO verification completed"
    log_info "Checksums generated: ${iso_file}.sha256 and ${iso_file}.md5"
}

cppkglist() {
    log_step "Copying package list..."
    if [[ -f "$BUILD_DIR/iso/arch/pkglist.x86_64.txt" ]]; then
        cp "$BUILD_DIR/iso/arch/pkglist.x86_64.txt" "$OUT_DIR/"
        log_success "Package list copied to output directory"
    else
        log_warning "Package list not found, skipping..."
    fi
}

rmezrepo() {
    log_step "Cleaning up temporary repository..."
    [[ -d "/opt/arafsk_repo" ]] && rm -rf /opt/arafsk_repo
    log_success "Temporary repository removed"
}

# ==========================================
# MAIN EXECUTION
# ==========================================

rootuser
prepreqs
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
backup_previous_iso
runmkarchiso
cppkglist
rmezrepo
verify_iso
