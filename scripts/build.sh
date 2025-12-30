#!/bin/bash
#
# Araf OS ISO Builder
# Advanced Arch Linux ISO creation script
# Author: Arafsk
# Version: 3.0
#

# ==========================================
# STRICT MODE & INITIAL SETUP
# ==========================================
set -euo pipefail
IFS=$'\n\t'

# ==========================================
# CONFIGURATION
# ==========================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly ARCHISO_DIR="/home/munna/DATA/iso-make/arafos-iso/archiso"
readonly BASE_DIR="/home/munna/DATA/iso-make"
readonly BUILD_DIR="${BASE_DIR}/build"
readonly OUT_DIR="${BASE_DIR}/out"
readonly RELENG_DIR="${BASE_DIR}/releng"
readonly BACKUP_DIR="${BASE_DIR}/backups"
readonly CACHE_DIR="${BASE_DIR}/cache"
readonly CONFIG_DIR="${BASE_DIR}/config"
readonly LOG_FILE="${BASE_DIR}/build_log_$(date +%Y%m%d_%H%M%S).log"
readonly CONFIG_FILE="${CONFIG_DIR}/builder.conf"

# ----------------------------------------
# Default Configuration
# ----------------------------------------
MYUSERNM="liveuser"
MYUSRPASSWD="1122"
RTPASSWD="1122"
MYHOSTNM="Araf_OS"
ISO_PREFIX="arafos"
ISO_EDITION="standard"
ISO_ARCH="x86_64"
ISO_LABEL="ARAFOS_$(date +%Y%m)"
VERBOSE=true
CLEAN_BUILD=true
BACKUP_ENABLED=true
SKIP_VERIFY=false
INTERACTIVE=true
PARALLEL_JOBS=$(nproc)
COMPRESSION_LEVEL=9
ENABLE_CUSTOM_REPO=true
ENABLE_TESTING_REPO=false
KEEP_CHROOT=false
SIGN_ISO=false
GPG_KEY=""
BUILD_PROFILE="standard"

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
    echo -e "${RED}✗ ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
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

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${DIM}🔍 DEBUG:${NC} $*" | tee -a "$LOG_FILE"
    fi
}

log_command() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${MAGENTA}\$ ${NC}${*}" | tee -a "$LOG_FILE"
    fi
}

# ==========================================
# UTILITY FUNCTIONS
# ==========================================
print_banner() {
    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║         ╔═╗╦═╗╦═╗╔═╗╔═╗  ╔═╗╔═╗                         ║
║         ║ ║╠╦╝╠╦╝║ ╦║╣   ╚═╗║╣                          ║
║         ╚═╝╩╚═╩╚═╚═╝╚═╝  ╚═╝╚═╝                         ║
║                                                          ║
║                 ISO Builder v3.0                         ║
║           Advanced Arch Linux ISO Creator                ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
}

show_progress() {
    local current=$1
    local total=$2
    local task=$3
    local width=50
    local percent=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))
    
    printf "\r${CYAN}[%3d%%]${NC} [${GREEN}%-${width}s${NC}] [%2d/%2d] %s" \
        "$percent" \
        "$(printf '%0.s=' $(seq 1 $completed))" \
        "$current" "$total" "$task"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

run_with_spinner() {
    local task="$1"
    shift
    
    echo -ne "${CYAN}▶${NC} ${task}... "
    "$@" &
    local pid=$!
    
    spinner "$pid"
    wait "$pid"
    
    if [[ $? -eq 0 ]]; then
        echo -e "\r${GREEN}✓${NC} ${task} completed"
    else
        echo -e "\r${RED}✗${NC} ${task} failed"
        return 1
    fi
}

check_dependencies() {
    log_step "Checking dependencies..."
    
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
            log_success "Dependencies installed"
        else
            log_error "Required dependencies missing"
            exit 1
        fi
    else
        log_success "All dependencies satisfied"
    fi
}

create_directory_structure() {
    log_step "Creating directory structure..."
    
    local directories=(
        "$BASE_DIR"
        "$BUILD_DIR"
        "$OUT_DIR"
        "$BACKUP_DIR"
        "$CACHE_DIR"
        "$CONFIG_DIR"
        "$BACKUP_DIR/iso"
        "$BACKUP_DIR/configs"
        "$CACHE_DIR/packages"
        "$CACHE_DIR/repo"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        log_debug "Created directory: $dir"
    done
    
    log_success "Directory structure created"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        log_warning "Configuration file not found, using defaults"
    fi
}

save_config() {
    log_step "Saving configuration..."
    
    cat > "$CONFIG_FILE" << EOF
# Araf OS ISO Builder Configuration
# Generated on $(date)

# User Configuration
MYUSERNM="$MYUSERNM"
MYHOSTNM="$MYHOSTNM"
ISO_PREFIX="$ISO_PREFIX"
ISO_EDITION="$ISO_EDITION"
ISO_ARCH="$ISO_ARCH"
BUILD_PROFILE="$BUILD_PROFILE"

# Build Options
PARALLEL_JOBS=$PARALLEL_JOBS
COMPRESSION_LEVEL=$COMPRESSION_LEVEL
ENABLE_CUSTOM_REPO=$ENABLE_CUSTOM_REPO
ENABLE_TESTING_REPO=$ENABLE_TESTING_REPO
SIGN_ISO=$SIGN_ISO
GPG_KEY="$GPG_KEY"

# Last Build Information
LAST_BUILD_DATE="$(date)"
LAST_BUILD_VERSION="3.0"
EOF
    
    log_success "Configuration saved to $CONFIG_FILE"
}

usage() {
    cat << EOF

Usage: $0 [OPTIONS]

Options:
    -u, --user USERNAME          Set username (default: $MYUSERNM)
    -p, --password              Prompt for passwords
    -h, --hostname HOSTNAME     Set hostname (default: $MYHOSTNM)
    -n, --name ISO_NAME         Set ISO name prefix (default: $ISO_PREFIX)
    -e, --edition EDITION       Set edition (default: $ISO_EDITION)
    -a, --arch ARCH             Set architecture (default: $ISO_ARCH)
    -c, --clean                 Clean previous build before starting
    -i, --interactive           Run in interactive mode
    -b, --backup                Backup previous ISO before building
    -v, --verbose               Enable verbose output
    -s, --skip-verify           Skip ISO verification
    -j, --jobs NUM              Number of parallel jobs (default: $PARALLEL_JOBS)
    -l, --compression LEVEL     Compression level (1-9, default: $COMPRESSION_LEVEL)
    -t, --testing               Enable testing repository
    -k, --keep-chroot          Keep chroot after build
    -g, --sign [KEY]           Sign ISO with GPG
    --profile PROFILE          Build profile (default: $BUILD_PROFILE)
    --no-custom-repo           Disable custom repository
    --list-profiles            List available profiles
    --version                  Show version information
    --help                     Show this help message

Environment Variables:
    MYUSRPASSWD                User password (prompted if not set)
    RTPASSWD                   Root password (prompted if not set)
    ISO_BUILDER_DEBUG          Enable debug mode

Examples:
    $0 -u myuser -h MyOS --clean
    $0 --interactive --backup -j 4
    $0 -c -l 6 --sign mykey
    $0 --profile minimal --no-custom-repo

Available Profiles:
    standard     - Standard desktop environment
    minimal      - Minimal system
    server       - Server edition
    developer    - Development tools included
    gaming       - Gaming optimized

EOF
}

show_version() {
    cat << EOF
Araf OS ISO Builder v3.0
Copyright (C) 2023 Arafsk
License: MIT
GitHub: https://github.com/arafsk/arafos-iso
EOF
}

list_profiles() {
    cat << EOF
Available Build Profiles:

  standard       - Full desktop environment with all applications
    Includes: GNOME, office suite, multimedia, utilities
    
  minimal        - Minimal system with basic tools
    Includes: Base system, network tools, terminal
    
  server         - Server optimized edition
    Includes: SSH, web server, database, monitoring tools
    
  developer      - Development environment
    Includes: IDEs, compilers, version control, containers
    
  gaming         - Gaming optimized system
    Includes: Steam, Wine, gaming drivers, performance tools

To use a profile: $0 --profile <name>
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                MYUSERNM="$2"
                shift 2
                ;;
            -p|--password)
                prompt_passwords
                shift
                ;;
            -h|--hostname)
                MYHOSTNM="$2"
                shift 2
                ;;
            -n|--name)
                ISO_PREFIX="$2"
                shift 2
                ;;
            -e|--edition)
                ISO_EDITION="$2"
                shift 2
                ;;
            -a|--arch)
                ISO_ARCH="$2"
                shift 2
                ;;
            -c|--clean)
                CLEAN_BUILD=true
                shift
                ;;
            -i|--interactive)
                INTERACTIVE=true
                shift
                ;;
            -b|--backup)
                BACKUP_ENABLED=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -s|--skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -l|--compression)
                COMPRESSION_LEVEL="$2"
                if [[ ! "$COMPRESSION_LEVEL" =~ ^[1-9]$ ]]; then
                    log_error "Compression level must be between 1 and 9"
                    exit 1
                fi
                shift 2
                ;;
            -t|--testing)
                ENABLE_TESTING_REPO=true
                shift
                ;;
            -k|--keep-chroot)
                KEEP_CHROOT=true
                shift
                ;;
            -g|--sign)
                SIGN_ISO=true
                if [[ -n "$2" ]] && [[ ! "$2" =~ ^- ]]; then
                    GPG_KEY="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --profile)
                BUILD_PROFILE="$2"
                shift 2
                ;;
            --no-custom-repo)
                ENABLE_CUSTOM_REPO=false
                shift
                ;;
            --list-profiles)
                list_profiles
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
}

prompt_passwords() {
    if [[ -z "$MYUSRPASSWD" ]]; then
        echo -n "Enter password for user '$MYUSERNM': "
        read -r -s MYUSRPASSWD
        echo
        
        echo -n "Confirm password: "
        read -r -s confirm
        echo
        
        if [[ "$MYUSRPASSWD" != "$confirm" ]]; then
            log_error "Passwords do not match"
            exit 1
        fi
    fi
    
    if [[ -z "$RTPASSWD" ]]; then
        echo -n "Enter root password: "
        read -r -s RTPASSWD
        echo
        
        echo -n "Confirm root password: "
        read -r -s confirm
        echo
        
        if [[ "$RTPASSWD" != "$confirm" ]]; then
            log_error "Passwords do not match"
            exit 1
        fi
    fi
}

interactive_setup() {
    print_banner
    
    echo -e "\n${BOLD}Interactive ISO Configuration${NC}\n"
    
    # Username
    read -p "Username [$MYUSERNM]: " input
    MYUSERNM="${input:-$MYUSERNM}"
    
    # Hostname
    read -p "Hostname [$MYHOSTNM]: " input
    MYHOSTNM="${input:-$MYHOSTNM}"
    
    # ISO Name
    read -p "ISO Name Prefix [$ISO_PREFIX]: " input
    ISO_PREFIX="${input:-$ISO_PREFIX}"
    
    # Edition
    echo -e "\nAvailable Editions:"
    echo "1) standard"
    echo "2) minimal"
    echo "3) server"
    echo "4) developer"
    echo "5) gaming"
    read -p "Select edition [1-5, default: 1]: " choice
    case $choice in
        2) ISO_EDITION="minimal" ;;
        3) ISO_EDITION="server" ;;
        4) ISO_EDITION="developer" ;;
        5) ISO_EDITION="gaming" ;;
        *) ISO_EDITION="standard" ;;
    esac
    
    # Passwords
    prompt_passwords
    
    # Build options
    read -p "Clean previous build? [y/N]: " -r
    [[ $REPLY =~ ^[Yy]$ ]] && CLEAN_BUILD=true
    
    read -p "Enable verbose output? [y/N]: " -r
    [[ $REPLY =~ ^[Yy]$ ]] && VERBOSE=true
    
    read -p "Number of parallel jobs [$PARALLEL_JOBS]: " input
    PARALLEL_JOBS="${input:-$PARALLEL_JOBS}"
    
    read -p "Compression level (1-9) [$COMPRESSION_LEVEL]: " input
    COMPRESSION_LEVEL="${input:-$COMPRESSION_LEVEL}"
    
    echo -e "\n${GREEN}Configuration complete!${NC}\n"
}

clean_previous_build() {
    log_step "Cleaning previous build..."
    
    local dirs_to_clean=(
        "$BUILD_DIR"
        "$RELENG_DIR"
    )
    
    for dir in "${dirs_to_clean[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_debug "Cleaned: $dir"
        fi
    done
    
    # Clean cache if requested
    if [[ "$CLEAN_BUILD" == true ]]; then
        if [[ -d "$CACHE_DIR/packages" ]]; then
            rm -rf "$CACHE_DIR/packages"/*
            log_debug "Cleaned package cache"
        fi
    fi
    
    log_success "Previous build cleaned"
}

backup_previous_iso() {
    if [[ "$BACKUP_ENABLED" != true ]]; then
        return 0
    fi
    
    log_step "Backing up previous ISO..."
    
    local iso_files=("$OUT_DIR"/*.iso)
    if [[ ${#iso_files[@]} -gt 0 ]] && [[ -f "${iso_files[0]}" ]]; then
        local backup_timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_subdir="$BACKUP_DIR/iso/$backup_timestamp"
        
        mkdir -p "$backup_subdir"
        
        # Move ISO and related files
        mv "$OUT_DIR"/*.iso "$backup_subdir/" 2>/dev/null || true
        mv "$OUT_DIR"/*.sha256 "$backup_subdir/" 2>/dev/null || true
        mv "$OUT_DIR"/*.md5 "$backup_subdir/" 2>/dev/null || true
        mv "$OUT_DIR"/*.sig "$backup_subdir/" 2>/dev/null || true
        mv "$OUT_DIR"/*.txt "$backup_subdir/" 2>/dev/null || true
        
        # Backup configuration
        cp "$CONFIG_FILE" "$BACKUP_DIR/configs/config_$backup_timestamp.conf" 2>/dev/null || true
        
        log_success "Backup created at: $backup_subdir"
        log_info "Backup includes: ISO, checksums, and configuration"
    else
        log_info "No previous ISO found to backup"
    fi
}

# ==========================================
# BUILD FUNCTIONS
# ==========================================
prepreqs() {
    log_step "Installing prerequisites..."
    
    if ! pacman -S --needed --noconfirm archiso mkinitcpio-archiso &>> "$LOG_FILE"; then
        log_error "Failed to install prerequisites"
        exit 1
    fi
    
    log_success "Prerequisites installed"
}

cpreleng() {
    log_step "Setting up releng configuration..."
    
    if [[ ! -d "/usr/share/archiso/configs/releng" ]]; then
        log_error "archiso releng configuration not found"
        exit 1
    fi
    
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
    
    log_success "Releng configuration set up"
}

apply_build_profile() {
    log_step "Applying build profile: $BUILD_PROFILE"
    
    local profile_dir="$ARCHISO_DIR/profiles/$BUILD_PROFILE"
    
    if [[ ! -d "$profile_dir" ]]; then
        log_warning "Profile directory not found: $profile_dir"
        log_info "Using standard configuration"
        return 0
    fi
    
    # Copy profile specific files
    if [[ -f "$profile_dir/packages.x86_64" ]]; then
        cp "$profile_dir/packages.x86_64" "$RELENG_DIR/"
        log_debug "Applied profile packages list"
    fi
    
    if [[ -f "$profile_dir/pacman.conf" ]]; then
        cp "$profile_dir/pacman.conf" "$RELENG_DIR/"
        log_debug "Applied profile pacman.conf"
    fi
    
    # Copy custom files from profile
    if [[ -d "$profile_dir/airootfs" ]]; then
        cp -r "$profile_dir/airootfs/"* "$RELENG_DIR/airootfs/" 2>/dev/null || true
        log_debug "Applied profile airootfs files"
    fi
    
    log_success "Build profile applied"
}

setup_custom_repository() {
    if [[ "$ENABLE_CUSTOM_REPO" != true ]]; then
        log_info "Custom repository disabled"
        return 0
    fi
    
    log_step "Setting up custom repository..."
    
    local repo_source="$ARCHISO_DIR/airootfs/opt/arafsk_repo"
    local repo_dest="/opt/arafsk_repo"
    
    if [[ ! -d "$repo_source" ]]; then
        log_warning "Custom repository source not found: $repo_source"
        return 0
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$repo_dest")"
    
    # Copy repository
    if [[ -d "$repo_dest" ]]; then
        rm -rf "$repo_dest"
    fi
    
    cp -r "$repo_source" "$repo_dest"
    
    # Create repository database
    if command -v repo-add &>/dev/null; then
        cd "$repo_dest"
        repo-add arafsk_repo.db.tar.gz *.pkg.tar.* 2>/dev/null || true
        cd - > /dev/null
    fi
    
    log_success "Custom repository set up at $repo_dest"
}

setup_pacman_conf() {
    log_step "Configuring pacman..."
    
    local pacman_conf="$RELENG_DIR/pacman.conf"
    
    # Enable parallel downloads
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' "$pacman_conf"
    sed -i "s/^ParallelDownloads = .*/ParallelDownloads = $PARALLEL_JOBS/" "$pacman_conf"
    
    # Add custom repository if enabled
    if [[ "$ENABLE_CUSTOM_REPO" == true ]] && [[ -d "/opt/arafsk_repo" ]]; then
        cat >> "$pacman_conf" << EOF

# Custom Araf OS Repository
[arafsk_repo]
SigLevel = Optional TrustAll
Server = file:///opt/arafsk_repo
EOF
        log_debug "Added custom repository to pacman.conf"
    fi
    
    # Enable testing repository if requested
    if [[ "$ENABLE_TESTING_REPO" == true ]]; then
        sed -i '/^#\[testing\]/,/^#Include/s/^#//' "$pacman_conf"
        log_debug "Enabled testing repository"
    fi
    
    # Enable multilib if x86_64
    if [[ "$ISO_ARCH" == "x86_64" ]]; then
        sed -i '/^#\[multilib\]/,/^#Include/s/^#//' "$pacman_conf"
        log_debug "Enabled multilib repository"
    fi
    
    log_success "Pacman configured"
}

configure_bootloaders() {
    log_step "Configuring bootloaders..."
    
    # Copy boot configurations
    if [[ -d "$ARCHISO_DIR/grub" ]]; then
        cp -r "$ARCHISO_DIR/grub" "$RELENG_DIR/"
    fi
    
    if [[ -d "$ARCHISO_DIR/efiboot" ]]; then
        cp -r "$ARCHISO_DIR/efiboot" "$RELENG_DIR/"
    fi
    
    if [[ -d "$ARCHISO_DIR/syslinux" ]]; then
        cp -r "$ARCHISO_DIR/syslinux" "$RELENG_DIR/"
    fi
    
    # Update bootloader configuration with hostname
    local boot_files=(
        "$RELENG_DIR/grub/grub.cfg"
        "$RELENG_DIR/syslinux/archiso_sys.cfg"
        "$RELENG_DIR/efiboot/loader/entries/archiso-x86_64.conf"
    )
    
    for file in "${boot_files[@]}"; do
        if [[ -f "$file" ]]; then
            sed -i "s/archiso/$MYHOSTNM/g" "$file"
            sed -i "s/Arch Linux/Araf OS/g" "$file"
        fi
    done
    
    log_success "Bootloaders configured"
}

copy_custom_files() {
    log_step "Copying custom files..."
    
    # Check if source directory exists
    if [[ ! -d "$ARCHISO_DIR/airootfs" ]]; then
        log_error "Custom files directory not found: $ARCHISO_DIR/airootfs"
        exit 1
    fi
    
    # Copy files with progress indicator
    local dirs=("etc" "opt" "usr" "root")
    local total=${#dirs[@]}
    local current=0
    
    for dir in "${dirs[@]}"; do
        current=$((current + 1))
        show_progress "$current" "$total" "Copying $dir"
        
        local source_dir="$ARCHISO_DIR/airootfs/$dir"
        local dest_dir="$RELENG_DIR/airootfs/$dir"
        
        if [[ -d "$source_dir" ]]; then
            mkdir -p "$dest_dir"
            cp -r "$source_dir"/* "$dest_dir"/ 2>/dev/null || true
        fi
    done
    
    echo
    log_success "Custom files copied"
}

setup_users() {
    log_step "Setting up users and groups..."
    
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
    
    log_success "Users and groups configured"
}

setup_systemd_services() {
    log_step "Configuring systemd services..."
    
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
    
    log_success "Systemd services configured"
}

build_iso() {
    log_step "Building ISO image..."
    
    local iso_name="${ISO_PREFIX}-${ISO_EDITION}-${ISO_ARCH}-$(date +%Y.%m.%d)"
    local build_cmd="mkarchiso"
    
    # Add verbose flag if enabled
    [[ "$VERBOSE" == true ]] && build_cmd="$build_cmd -v"
    
    # Add compression level
    build_cmd="$build_cmd -L $COMPRESSION_LEVEL"
    
    # Build the ISO
    log_command "$build_cmd -w $BUILD_DIR -o $OUT_DIR $RELENG_DIR"
    
    if ! $build_cmd -w "$BUILD_DIR" -o "$OUT_DIR" "$RELENG_DIR" &>> "$LOG_FILE"; then
        log_error "ISO build failed"
        return 1
    fi
    
    # Rename ISO file
    local iso_file=$(find "$OUT_DIR" -name "*.iso" -type f | head -n1)
    if [[ -n "$iso_file" ]]; then
        local new_name="$OUT_DIR/$iso_name.iso"
        mv "$iso_file" "$new_name"
        log_debug "Renamed ISO to: $(basename "$new_name")"
    fi
    
    log_success "ISO build completed"
    return 0
}

verify_iso() {
    if [[ "$SKIP_VERIFY" == true ]]; then
        log_info "Skipping ISO verification"
        return 0
    fi
    
    log_step "Verifying ISO file..."
    
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
        log_success "SHA256 checksum verified"
    else
        log_error "SHA256 checksum verification failed"
        return 1
    fi
    
    if md5sum -c "${base_name}.md5" &>/dev/null; then
        log_success "MD5 checksum verified"
    else
        log_error "MD5 checksum verification failed"
        return 1
    fi
    
    # Test ISO reading
    if command -v isoinfo &>/dev/null; then
        if isoinfo -d -i "$iso_file" &>/dev/null; then
            log_success "ISO structure validated"
        else
            log_warning "ISO structure validation failed"
        fi
    fi
    
    log_success "ISO verification completed"
}

sign_iso() {
    if [[ "$SIGN_ISO" != true ]]; then
        return 0
    fi
    
    log_step "Signing ISO file..."
    
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
        log_success "ISO signed successfully"
    else
        log_warning "Failed to sign ISO"
    fi
}

generate_build_report() {
    log_step "Generating build report..."
    
    local iso_file=$(find "$OUT_DIR" -name "*.iso" -type f | head -n1)
    local report_file="$OUT_DIR/build-report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Araf OS ISO Build Report
========================

Build Information:
-----------------
Build Date:      $(date)
Builder Version: 3.0
Build Profile:   $BUILD_PROFILE
Edition:         $ISO_EDITION
Architecture:    $ISO_ARCH

System Configuration:
--------------------
Hostname:        $MYHOSTNM
Username:        $MYUSERNM
User UID:        1000
User GID:        1000

ISO Details:
------------
ISO File:        $(basename "$iso_file")
ISO Size:        $(du -h "$iso_file" | cut -f1)
Build Directory: $BUILD_DIR
Output Directory: $OUT_DIR

Build Options:
--------------
Parallel Jobs:   $PARALLEL_JOBS
Compression:     Level $COMPRESSION_LEVEL
Custom Repo:     $ENABLE_CUSTOM_REPO
Testing Repo:    $ENABLE_TESTING_REPO
ISO Signed:      $SIGN_ISO

Checksums:
----------
$(cat "${iso_file}.sha256" 2>/dev/null || echo "SHA256: Not available")
$(cat "${iso_file}.md5" 2>/dev/null || echo "MD5: Not available")

Build Log:
----------
Log file: $LOG_FILE

EOF
    
    # Add package list if available
    if [[ -f "$BUILD_DIR/iso/arch/pkglist.x86_64.txt" ]]; then
        cp "$BUILD_DIR/iso/arch/pkglist.x86_64.txt" "$OUT_DIR/"
        echo "Package list: pkglist.x86_64.txt" >> "$report_file"
    fi
    
    log_success "Build report generated: $(basename "$report_file")"
}

cleanup() {
    log_step "Performing cleanup..."
    
    # Remove custom repository from /opt
    if [[ -d "/opt/arafsk_repo" ]] && [[ "$ENABLE_CUSTOM_REPO" == true ]]; then
        rm -rf "/opt/arafsk_repo"
        log_debug "Removed custom repository"
    fi
    
    # Remove build directory if not keeping chroot
    if [[ "$KEEP_CHROOT" != true ]] && [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
        log_debug "Removed build directory"
    fi
    
    # Remove releng directory
    if [[ -d "$RELENG_DIR" ]]; then
        rm -rf "$RELENG_DIR"
        log_debug "Removed releng directory"
    fi
    
    log_success "Cleanup completed"
}

show_summary() {
    local iso_file=$(find "$OUT_DIR" -name "*.iso" -type f | head -n1)
    
    cat << EOF

${BOLD}═══════════════════════════════════════════════════════════════${NC}
${GREEN}                    BUILD SUCCESSFUL!                         ${NC}
${BOLD}═══════════════════════════════════════════════════════════════${NC}

${BOLD}Output Files:${NC}
  ISO Image:      ${GREEN}$(basename "$iso_file")${NC}
  SHA256 Checksum: $(basename "$iso_file").sha256
  MD5 Checksum:    $(basename "$iso_file").md5
  Build Report:    build-report_*.txt
  Package List:    pkglist.x86_64.txt

${BOLD}Build Information:${NC}
  Hostname:        $MYHOSTNM
  Username:        $MYUSERNM
  Edition:         $ISO_EDITION
  Architecture:    $ISO_ARCH
  Build Profile:   $BUILD_PROFILE

${BOLD}File Locations:${NC}
  Output Directory: $OUT_DIR
  Log File:        $LOG_FILE
  Backup Directory: $BACKUP_DIR

${BOLD}Next Steps:${NC}
  1. Test the ISO in a virtual machine
  2. Burn to USB: sudo dd if=$(basename "$iso_file") of=/dev/sdX bs=4M status=progress
  3. Verify checksums before distribution

${YELLOW}Note:${NC} The ISO uses the following credentials:
  - Username: $MYUSERNM
  - Password: ${MYUSRPASSWD:-1122}
  - Root Password: ${RTPASSWD:-1122}

${BOLD}═══════════════════════════════════════════════════════════════${NC}

EOF
}

# ==========================================
# ERROR HANDLING
# ==========================================
trap 'handle_error $LINENO' ERR
trap 'handle_interrupt' INT

handle_error() {
    local line=$1
    local exit_code=$?
    
    log_error "Build failed at line $line with exit code: $exit_code"
    log_error "Check the log file for details: $LOG_FILE"
    
    # Attempt to save current state
    if [[ -d "$RELENG_DIR" ]]; then
        local rescue_dir="$BACKUP_DIR/rescue_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$rescue_dir"
        cp -r "$RELENG_DIR" "$rescue_dir/" 2>/dev/null || true
        log_info "Rescue copy saved to: $rescue_dir"
    fi
    
    cleanup
    exit "$exit_code"
}

handle_interrupt() {
    echo
    log_error "Build interrupted by user"
    cleanup
    exit 130
}

# ==========================================
# MAIN EXECUTION
# ==========================================
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load configuration
    load_config
    
    # Interactive mode
    if [[ "$INTERACTIVE" == true ]]; then
        interactive_setup
    fi
    
    # Check if passwords are set
    if [[ -z "$MYUSRPASSWD" ]] || [[ -z "$RTPASSWD" ]]; then
        if [[ "$INTERACTIVE" != true ]]; then
            prompt_passwords
        fi
    fi
    
    # Set default passwords if still empty
    MYUSRPASSWD="${MYUSRPASSWD:-1122}"
    RTPASSWD="${RTPASSWD:-1122}"
    
    # Print banner
    print_banner
    
    # Check root
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Please run: sudo $0 $*"
        exit 1
    fi
    
    # Create directories
    create_directory_structure
    
    # Check dependencies
    check_dependencies
    
    # Clean previous build if requested
    if [[ "$CLEAN_BUILD" == true ]]; then
        clean_previous_build
    fi
    
    # Backup previous ISO
    backup_previous_iso
    
    # Start logging
    log "Starting Araf OS ISO build v3.0"
    log "Build started at: $(date)"
    log "Configuration:"
    log "  Username: $MYUSERNM"
    log "  Hostname: $MYHOSTNM"
    log "  Edition: $ISO_EDITION"
    log "  Profile: $BUILD_PROFILE"
    log "  Architecture: $ISO_ARCH"
    
    # Build steps
    local steps=(
        "prepreqs"
        "cpreleng"
        "apply_build_profile"
        "setup_custom_repository"
        "setup_pacman_conf"
        "configure_bootloaders"
        "copy_custom_files"
        "setup_users"
        "setup_systemd_services"
        "build_iso"
        "verify_iso"
        "sign_iso"
        "generate_build_report"
        "save_config"
    )
    
    # Execute build steps
    local total_steps=${#steps[@]}
    local current_step=0
    
    for step in "${steps[@]}"; do
        current_step=$((current_step + 1))
        log_step "Step $current_step/$total_steps: ${step//_/ }"
        
        if ! $step; then
            log_error "Step failed: $step"
            exit 1
        fi
    done
    
    # Cleanup
    cleanup
    
    # Show summary
    show_summary
    
    log_success "Build completed successfully at $(date)"
}

# Run main function
main "$@"
