#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hyprland-Dots Packages #
# edit your packages desired here.
# WARNING! If you remove packages here, dotfiles may not work properly.
# and also, ensure that packages are present in Debian Official Repo

# add packages wanted here
Extra=(
    libpci-dev
)

# packages needed
hypr_package=(
    cliphist
    grim
    gvfs
    gvfs-backends
    glslang-dev   # Needed to build hyprland
    glslang-tools # Needed to build hyprland
    lua5.4        # Needed to build Hyprland 0.55
    liblua5.4-dev # Needed to build Hyprland 0.55
    xxd           #  Needed to build Hyprland 0.55
    inxi
    ffmpeg
    7zip
    fd-find
    fzf
    imagemagick
    jq
    poppler-utils
    ripgrep
    zoxide
    kitty
    nano
    pavucontrol
    pulseaudio-utils
    playerctl
    mate-polkit
    polkit-kde-agent-1
    python3-requests
    python3-pip
    qt5ct
    libqt5quick5
    libqt5qml5
    qt6-declarative-dev
    qt-style-kvantum-themes
    qt-style-kvantum
    qt6ct
    slurp
    swappy
    sway-notification-center
    unzip
    waybar
    wget
    wl-clipboard
    wlogout
    xdg-user-dirs
    xdg-utils
    xxd
    yad
)

# the following packages can be deleted. however, dotfiles may not work properly
hypr_package_2=(
    brightnessctl
    btop
    cava
    fastfetch
    loupe
    gnome-system-monitor
    mousepad
    mpv
    mpv-mpris
    nwg-look
    nwg-displays
    nvtop
    pamixer
    qalculate-gtk
)
# Optional packages used by some dotfiles/features.
# These are installed when available in current APT sources.
hypr_optional_package=(
    qml6-module-org-hyprland-style # Provides org.hyprland.style for QT_QUICK_CONTROLS_STYLE
)

# packages to force reinstall (only when HYPR_FORCE_REINSTALL=1)
force=(
    imagemagick
)

# List of packages to uninstall as it conflicts with swaync or causing swaync to not function properly
uninstall=(
    mako
    cargo
    rofi-wayland
)

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || {
    echo "${ERROR} Failed to change directory to $PARENT_DIR"
    exit 1
}

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
    echo "Failed to source Global_functions.sh"
    exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_hypr-pkgs.log"
# Detect installed rofi version (from PATH, including /usr/local builds)
get_rofi_version() {
    if command -v rofi >/dev/null 2>&1; then
        rofi -version 2>/dev/null | awk 'NR==1 {print $2}'
    fi
}

package_has_candidate() {
    apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -vq "(none)"
}

detect_suite() {
    local c=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        c="${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}"
    fi
    if [[ -z "$c" ]] && command -v lsb_release >/dev/null 2>&1; then
        c="$(lsb_release -cs 2>/dev/null || true)"
    fi
    printf '%s' "$c"
}

rofi_installed_ver="$(get_rofi_version || true)"
rofi_ok=0
if [ -n "$rofi_installed_ver" ]; then
    if dpkg --compare-versions "$rofi_installed_ver" ge "2.0.0"; then
        rofi_ok=1
        echo "${INFO} Detected rofi ${YELLOW}$rofi_installed_ver${RESET} (>= 2.0.0). Skipping rofi uninstall." | tee -a "$LOG"
    fi
fi

# conflicting packages removal
overall_failed=0
printf "\n%s - ${SKY_BLUE}Removing some packages${RESET} as it conflicts with KooL's Hyprland Dots \n" "${NOTE}"
for PKG in "${uninstall[@]}"; do
    if [ "$rofi_ok" -eq 1 ] && { [ "$PKG" = "rofi" ] || [ "$PKG" = "rofi-wayland" ]; }; then
        echo "${INFO} Skipping uninstall of ${YELLOW}$PKG${RESET} (rofi >= 2.0.0 detected)." | tee -a "$LOG"
        continue
    fi
    uninstall_package "$PKG" 2>&1 | tee -a "$LOG"
    if [ $? -ne 0 ]; then
        overall_failed=1
    fi
done

if [ $overall_failed -ne 0 ]; then
    echo -e "${ERROR} Some packages failed to uninstall. Please check the log."
fi

printf "\n%.0s" {1..1}

# Installation of main components
printf "\n%s - Installing ${SKY_BLUE}KooL's hyprland necessary packages${RESET} .... \n" "${NOTE}"

for PKG1 in "${hypr_package[@]}" "${hypr_package_2[@]}" "${Extra[@]}"; do
    if [ "${HYPR_INSTALL_MODE:-}" = "debian" ] && [ "${DEBIAN_SUITE:-}" = "trixie" ] && [ "$PKG1" = "waybar" ]; then
        install_package_target "$PKG1" "trixie-backports"
    else
        install_package "$PKG1" "$LOG"
    fi
done

# Optional package installs (non-fatal when unavailable in the current suite)
CURRENT_SUITE="${DEBIAN_SUITE:-$(detect_suite)}"
for PKG_OPT in "${hypr_optional_package[@]}"; do
    if package_has_candidate "$PKG_OPT"; then
        if [ "${HYPR_INSTALL_MODE:-}" = "debian" ] && [ "${CURRENT_SUITE:-}" = "trixie" ] && target_release_available_for_pkg "$PKG_OPT" "trixie-backports"; then
            install_package_target "$PKG_OPT" "trixie-backports"
        else
            install_package "$PKG_OPT" "$LOG"
        fi
    elif [ "${CURRENT_SUITE:-}" = "trixie" ] && target_release_available_for_pkg "$PKG_OPT" "trixie-backports"; then
        echo "${INFO} Optional package ${YELLOW}$PKG_OPT${RESET} is not available in trixie main. Falling back to trixie-backports." | tee -a "$LOG"
        install_package_target "$PKG_OPT" "trixie-backports"
    else
        echo "${NOTE} Optional package ${YELLOW}$PKG_OPT${RESET} is not available in current APT sources. Skipping." | tee -a "$LOG"
    fi
done

printf "\n%.0s" {1..1}

if [ "${HYPR_FORCE_REINSTALL:-0}" = "1" ]; then
    for PKG2 in "${force[@]}"; do
        re_install_package "$PKG2" "$LOG"
    done
else
    echo "${INFO} Skipping forced reinstalls (enable with --force-reinstall)." | tee -a "$LOG"
fi

printf "\n%.0s" {1..1}
# Install yazi via dedicated repo script when missing (Debian repo may not include it)
if ! command -v yazi >/dev/null 2>&1; then
    YAZI_INSTALLER="$PARENT_DIR/install-scripts/yazi.sh"
    echo "${INFO} ${YELLOW}yazi${RESET} not found. Running dedicated yazi installer..." | tee -a "$LOG"
    if [ -x "$YAZI_INSTALLER" ]; then
        "$YAZI_INSTALLER"
    elif [ -f "$YAZI_INSTALLER" ]; then
        bash "$YAZI_INSTALLER"
    else
        echo "${ERROR} Could not find ${YELLOW}yazi.sh${RESET} at $YAZI_INSTALLER" | tee -a "$LOG"
        exit 1
    fi
else
    echo "${INFO} ${YELLOW}yazi${RESET} is already installed. Skipping dedicated installer." | tee -a "$LOG"
fi
# install YAD from assets. NOTE This is downloaded from SID repo and sometimes
# Trixie is removing YAD for some strange reasons
# Check if yad is installed
if ! command -v yad &>/dev/null; then
    echo "${INFO} Installing ${YELLOW}YAD from assets${RESET} ..."
    sudo dpkg -i assets/yad_0.40.0-1+b2_amd64.deb
    sudo apt install -f -y
    echo "${INFO} ${YELLOW}YAD from assets${RESET} succesfully installed ..."
fi

printf "\n%.0s" {1..2}

# Install up-to-date Rust
echo "${INFO} Installing most ${YELLOW}up to date Rust compiler${RESET} ..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1 | tee -a "$LOG"
source "$HOME/.cargo/env"

## making brightnessctl work
sudo chmod +s $(which brightnessctl) 2>&1 | tee -a "$LOG" || true

printf "\n%.0s" {1..2}
