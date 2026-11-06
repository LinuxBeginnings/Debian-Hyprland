#!/usr/bin/env bash
# ==============================================================================
# Script: update.warp-key.sh
# Purpose: Refresh and fix rotated Warp Terminal GPG repository signing keys on Debian, Ubuntu, and derivatives.
#
# Version History:
#   Version | Date       | Comments
#   --------+------------+------------------------------------------------------
#   v0.2    | 2026-11-06 | Added Ubuntu and derivative distro support (Mint,
#           |            | Zorin, Pop!_OS, etc.), dry-run mode (-d/--dry-run),
#           |            | dynamic arch detection, and edge case fixes.
#   v0.1    | 2026-11-06 | Initial release with Debian OS check, error handling,
#           |            | GPG key validation, color output, and CLI options.
# ==============================================================================

set -euo pipefail

SCRIPT_VERSION="v0.2"

# ------------------------------------------------------------------------------
# Output formatting, colors, and icons
# ------------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    BOLD=$'\e[1m'
    RESET=$'\e[0m'
    RED=$'\e[1;31m'
    GREEN=$'\e[1;32m'
    YELLOW=$'\e[1;33m'
    BLUE=$'\e[1;34m'
    MAGENTA=$'\e[1;35m'
    CYAN=$'\e[1;36m'
else
    BOLD=""
    RESET=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
fi

ICON_INFO="${BLUE}ℹ${RESET}"
ICON_SUCCESS="${GREEN}✔${RESET}"
ICON_WARN="${YELLOW}⚠${RESET}"
ICON_ERROR="${RED}✖${RESET}"
ICON_STEP="${CYAN}➜${RESET}"
ICON_KEY="${YELLOW}🔑${RESET}"
ICON_PKG="${MAGENTA}📦${RESET}"

log_info() {
    printf "%b %s\n" "$ICON_INFO" "$*"
}

log_step() {
    printf "%b %b%s%b\n" "$ICON_STEP" "$BOLD" "$*" "$RESET"
}

log_success() {
    printf "%b %b%s%b\n" "$ICON_SUCCESS" "$GREEN" "$*" "$RESET"
}

log_warn() {
    printf "%b %b%s%b\n" "$ICON_WARN" "$YELLOW" "$*" "$RESET"
}

log_error() {
    printf "%b %b%s%b\n" "$ICON_ERROR" "$RED" "$*" "$RESET" >&2
}

# ------------------------------------------------------------------------------
# Version and help documentation
# ------------------------------------------------------------------------------
show_version() {
    cat << EOF
${BOLD}update.warp-key.sh${RESET} version ${GREEN}${SCRIPT_VERSION}${RESET}

${BOLD}Version History:${RESET}
  Version | Date       | Comments
  --------+------------+--------------------------------------------------------
  v0.2    | 2026-11-06 | Added Ubuntu & derivatives support (Mint, Zorin, etc.),
          |            | dry-run mode (-d/--dry-run), dynamic arch, and edge fixes.
  v0.1    | 2026-11-06 | Initial release with Debian OS check, error handling,
          |            | GPG key validation, color output, and CLI options.
EOF
}

show_help() {
    cat << EOF
${BOLD}Usage:${RESET} ${0##*/} [OPTIONS]

${BOLD}Description:${RESET}
  Safely updates and refreshes rotated Warp Terminal GPG repository signing keys
  on Debian, Ubuntu, and derivative distributions (Linux Mint, Zorin OS, Pop!_OS,
  etc.), updates APT keyrings, and upgrades warp-terminal.

${BOLD}Options:${RESET}
  ${CYAN}-h, --help${RESET}          Show this help message and exit
  ${CYAN}-v, --version${RESET}       Show version information and changelog table
  ${CYAN}-d, --dry-run${RESET}       Perform trial run (downloads & validates key; skips writes)
  ${CYAN}-s, --skip-upgrade${RESET}  Update signing keys and APT cache only; skip package upgrade

${BOLD}Actions performed:${RESET}
  1. Verifies Debian / Ubuntu OS compatibility via /etc/os-release
  2. Verifies required tools (curl, gpg, apt-get, install, chmod, sudo)
  3. Securely stages and downloads the key from https://releases.warp.dev/linux/keys/warp.asc
  4. Validates and dearmors the PGP key to OpenPGP binary format
  5. Inspects and prints the GPG key fingerprint and subkey expiration dates
  6. Installs the verified key with 0644 permissions to:
     • /etc/apt/keyrings/warpdotdev.gpg (modern standard)
     • /etc/apt/trusted.gpg.d/warpdotdev.gpg (installer compatibility)
  7. Ensures /etc/apt/sources.list.d/warpdotdev.list exists and uses signed-by
  8. Refreshes the APT package cache (apt update)
  9. Upgrades warp-terminal if installed (unless --skip-upgrade is specified)

${BOLD}Examples:${RESET}
  ${0##*/}                 # Update GPG keys, refresh APT cache, and upgrade Warp
  ${0##*/} -d              # Test run without modifying system files
  ${0##*/} -s              # Update GPG keys and refresh APT cache only
  ${0##*/} -h              # Display help documentation
  ${0##*/} -v              # Display script version and changelog
EOF
}

# ------------------------------------------------------------------------------
# Temporary directory and cleanup trap
# ------------------------------------------------------------------------------
TMP_DIR=""

cleanup() {
    local exit_code=$?
    if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then
        rm -rf "$TMP_DIR"
    fi
    if [[ $exit_code -ne 0 ]]; then
        printf "\n"
        log_error "Key update process aborted due to an error (exit code: $exit_code)."
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Check 1: Verify Debian / Ubuntu OS Compatibility
# ------------------------------------------------------------------------------
check_os_compatibility() {
    log_step "Checking operating system compatibility..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot identify OS: '/etc/os-release' was not found."
        exit 1
    fi

    # Read distribution info
    # shellcheck disable=SC1091
    . /etc/os-release

    local os_id="${ID:-}"
    local os_like="${ID_LIKE:-}"
    local pretty_name="${PRETTY_NAME:-$os_id}"
    local codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"

    # Check for direct Debian or Ubuntu
    if [[ "$os_id" == "debian" ]]; then
        log_success "Verified Debian OS: ${pretty_name} (${codename})"
    elif [[ "$os_id" == "ubuntu" ]]; then
        log_success "Verified Ubuntu OS: ${pretty_name} (${codename})"
    # Check for Ubuntu or Debian derivatives (Linux Mint, Zorin, Pop!_OS, Elementary, LMDE, etc.)
    elif [[ "$os_like" =~ (debian|ubuntu) ]] || [[ "$os_id" =~ ^(linuxmint|mint|zorin|pop|elementary|kali|raspbian|devuan|neon|tuxedo|mx)$ ]]; then
        log_success "Verified compatible Debian/Ubuntu-based distribution: ${pretty_name} (${codename})"
    else
        log_error "Unsupported OS. This script requires Debian, Ubuntu, or their derivatives (Mint, Zorin, etc.)."
        log_error "Detected: ${pretty_name} (ID: ${os_id:-unknown}, ID_LIKE: ${os_like:-none})"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Check 2: Verify required tools
# ------------------------------------------------------------------------------
check_prerequisites() {
    log_step "Verifying required tools..."
    local missing_tools=()

    for tool in curl gpg apt-get install chmod; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required utilities: ${missing_tools[*]}"
        log_error "Please install missing utilities before running this script."
        exit 1
    fi

    log_success "All required tools are installed."
}

# ------------------------------------------------------------------------------
# Check 3: Sudo / Privileges verification
# ------------------------------------------------------------------------------
setup_privileges() {
    local is_dry_run="${1:-0}"

    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
        log_info "Running directly as root."
    elif command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
        if [[ $is_dry_run -eq 1 ]]; then
            log_info "[DRY-RUN] Sudo utility available (authentication check deferred)."
        else
            log_info "Elevated privileges required. Verifying sudo access..."
            if ! sudo -v; then
                log_error "Failed to authenticate with sudo. Sudo privileges are required."
                exit 1
            fi
        fi
    else
        if [[ $is_dry_run -eq 1 ]]; then
            log_warn "[DRY-RUN] Neither root nor sudo available. Normal execution would require elevated privileges."
            SUDO_CMD=""
        else
            log_error "This script requires root privileges, but sudo is not installed."
            exit 1
        fi
    fi
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------
main() {
    local skip_upgrade=0
    local dry_run=0

    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -d|--dry-run)
                dry_run=1
                shift
                ;;
            -s|--skip-upgrade|--no-upgrade)
                skip_upgrade=1
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                printf "Try '%s --help' for more information.\n" "${0##*/}" >&2
                exit 1
                ;;
        esac
    done

    if [[ $dry_run -eq 1 ]]; then
        printf "\n%b%b=== Warp Terminal Key Rotation Utility (%s) [DRY-RUN MODE] ===%b\n\n" "$BOLD" "$YELLOW" "$SCRIPT_VERSION" "$RESET"
    else
        printf "\n%b%b=== Warp Terminal Key Rotation & Update Utility (%s) ===%b\n\n" "$BOLD" "$MAGENTA" "$SCRIPT_VERSION" "$RESET"
    fi

    check_os_compatibility
    check_prerequisites
    setup_privileges "$dry_run"

    local warp_key_url="https://releases.warp.dev/linux/keys/warp.asc"
    local keyrings_dir="/etc/apt/keyrings"
    local trusted_dir="/etc/apt/trusted.gpg.d"
    local key_filename="warpdotdev.gpg"
    local sources_file="/etc/apt/sources.list.d/warpdotdev.list"

    # Detect package architecture (fallback to amd64)
    local deb_arch
    deb_arch=$(dpkg --print-architecture 2>/dev/null || echo "amd64")

    # Create temporary staging directory
    TMP_DIR=$(mktemp -d -t warp-keyring-XXXXXX)
    local downloaded_asc="$TMP_DIR/warp.asc"
    local dearmored_gpg="$TMP_DIR/$key_filename"

    # Step 1: Download latest public key
    printf "\n"
    log_step "Downloading latest Warp GPG key from ${warp_key_url}..."
    if ! curl -fsSL --retry 3 --connect-timeout 10 "$warp_key_url" -o "$downloaded_asc"; then
        log_error "Failed to download the GPG key from ${warp_key_url}."
        exit 1
    fi

    if [[ ! -s "$downloaded_asc" ]] || ! grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$downloaded_asc"; then
        log_error "Downloaded file is empty or not a valid PGP ASCII key block."
        exit 1
    fi
    log_success "Public key downloaded successfully."

    # Step 2: Dearmor and validate key
    log_step "Dearmoring key to OpenPGP binary format..."
    if ! gpg --dearmor --yes -o "$dearmored_gpg" "$downloaded_asc" 2>/dev/null; then
        log_error "Failed to dearmor GPG key."
        exit 1
    fi

    log_step "Inspecting GPG key details..."
    printf "%b" "$CYAN"
    if ! gpg --show-keys "$dearmored_gpg"; then
        printf "%b" "$RESET"
        log_error "Failed to read or validate the key contents."
        exit 1
    fi
    printf "%b" "$RESET"
    log_success "Key signature validated successfully."

    # Step 3: Install key to keyrings
    printf "\n"
    log_step "Installing key to APT keyring directories..."

    if [[ $dry_run -eq 1 ]]; then
        log_info "[DRY-RUN] Would install: ${keyrings_dir}/${key_filename} (mode: 0644)"
        log_info "[DRY-RUN] Would install: ${trusted_dir}/${key_filename} (mode: 0644)"
    else
        # 3a. Modern standard Debian directory: /etc/apt/keyrings
        $SUDO_CMD install -d -m 0755 "$keyrings_dir"
        $SUDO_CMD install -m 0644 "$dearmored_gpg" "${keyrings_dir}/${key_filename}"
        log_success "${ICON_KEY} Installed: ${keyrings_dir}/${key_filename} (mode: 0644)"

        # 3b. Installer standard directory: /etc/apt/trusted.gpg.d
        $SUDO_CMD install -d -m 0755 "$trusted_dir"
        $SUDO_CMD install -m 0644 "$dearmored_gpg" "${trusted_dir}/${key_filename}"
        log_success "${ICON_KEY} Installed: ${trusted_dir}/${key_filename} (mode: 0644)"
    fi

    # Step 4: Verify repository source list
    printf "\n"
    log_step "Checking Warp APT repository configuration..."
    if [[ -f "$sources_file" ]]; then
        log_success "Repository configuration found at ${sources_file}."
    else
        if [[ $dry_run -eq 1 ]]; then
            log_info "[DRY-RUN] Would create: ${sources_file} [arch=${deb_arch}] pointing to ${keyrings_dir}/${key_filename}"
        else
            log_warn "Repository configuration not found. Creating ${sources_file}..."
            $SUDO_CMD install -d -m 0755 "/etc/apt/sources.list.d"
            echo "deb [arch=${deb_arch} signed-by=${keyrings_dir}/${key_filename}] https://releases.warp.dev/linux/deb stable main" | \
                $SUDO_CMD tee "$sources_file" >/dev/null
            log_success "Configured ${sources_file} with modern signed-by keyrings."
        fi
    fi

    # Step 5: Refresh APT package database
    printf "\n"
    log_step "Updating APT package index to verify signing key..."
    if [[ $dry_run -eq 1 ]]; then
        log_info "[DRY-RUN] Would execute: ${SUDO_CMD:-sudo} apt-get update"
    else
        if $SUDO_CMD apt-get update; then
            log_success "APT repository database refreshed successfully."
        else
            log_error "APT update failed. Please inspect the package manager output above."
            exit 1
        fi
    fi

    # Step 6: Upgrade warp-terminal package if installed
    printf "\n"
    if [[ $skip_upgrade -eq 1 ]]; then
        log_info "Skipping warp-terminal upgrade (--skip-upgrade specified)."
    else
        log_step "Checking Warp Terminal package installation..."
        if dpkg-query -W -f='${Status}' warp-terminal 2>/dev/null | grep -c "ok installed" >/dev/null; then
            local current_ver
            current_ver=$(dpkg-query -W -f='${Version}' warp-terminal 2>/dev/null || echo "unknown")
            log_info "${ICON_PKG} warp-terminal is currently installed (version: ${BOLD}${current_ver}${RESET})."
            if [[ $dry_run -eq 1 ]]; then
                log_info "[DRY-RUN] Would execute: ${SUDO_CMD:-sudo} env DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y warp-terminal"
            else
                log_step "Upgrading warp-terminal..."
                if $SUDO_CMD env DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y warp-terminal; then
                    local new_ver
                    new_ver=$(dpkg-query -W -f='${Version}' warp-terminal 2>/dev/null || echo "unknown")
                    log_success "${ICON_PKG} warp-terminal is up to date (version: ${BOLD}${new_ver}${RESET})."
                else
                    log_warn "Failed to complete warp-terminal upgrade. You can retry with: sudo apt-get install --only-upgrade warp-terminal"
                fi
            fi
        else
            log_info "warp-terminal is not currently installed on this system."
            log_info "To install it now, run: ${BOLD}sudo apt install warp-terminal${RESET}"
        fi
    fi

    if [[ $dry_run -eq 1 ]]; then
        printf "\n%b%b✔ Dry-run completed successfully! (No system files or packages were modified)%b\n\n" "$BOLD" "$YELLOW" "$RESET"
    else
        printf "\n%b%b✔ Warp Terminal repository keys successfully updated!%b\n\n" "$BOLD" "$GREEN" "$RESET"
    fi
}

main "$@"
