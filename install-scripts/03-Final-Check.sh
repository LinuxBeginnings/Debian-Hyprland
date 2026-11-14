#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Final checking if packages are installed
# NOTE: These package checks are only the essentials

packages=(
    imagemagick
    7zip
    fd-find
    ffmpeg
    fzf
    poppler-utils
    ripgrep
    sway-notification-center
    wl-clipboard
    cliphist
    wlogout
    kitty
    lua5.4
    yazi
    zoxide
    libopengl-dev
    libglvnd-dev
    libgl-dev
    libglx-dev
    network-manager
    # runtime packages installed by 01-hypr-pkgs.sh that keybinds/scripts rely on
    brightnessctl
    grim
    slurp
    swappy
    pavucontrol
    polkit-kde-agent-1
    qalculate-gtk # calculator keybind (SUPER ALT C)
    xdg-utils
    xdg-desktop-portal
    xdg-desktop-portal-gtk
)
# qml6-module-org-hyprland-style is verified separately (see is_qml_hyprland_style_loadable)
# because it ships no binary and an installed package alone does not mean Qt can import it.

# Essential binaries that should exist in PATH
# (works for both /usr/local/bin source installs and /usr/bin Debian package installs)
required_bins=(
    Hyprland
    rofi
    hypridle
    hyprlock
    wallust
    awww
    nwg-dock-hyprland
    hyprland-dialog
    luac
)

# Function to check if source-built waybar is installed
# Source builds install to /usr/local/bin; APT installs to /usr/bin.
is_source_waybar_installed() {
    if [ -x "/usr/local/bin/waybar" ]; then
        return 0
    fi
    if command -v waybar >/dev/null 2>&1; then
        local ver_line
        ver_line="$(waybar --version 2>&1 | grep -i 'waybar v' || true)"
        if echo "$ver_line" | grep -q -E "branch|g[0-9a-f]{7}"; then
            return 0
        fi
    fi
    return 1
}

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
LOG="Install-Logs/00_CHECK-$(date +%d-%H%M%S)_installed.log"

printf "\n%s - Final Check if Essential packages were installed \n" "${NOTE}"
# Initialize an empty array to hold missing packages
missing=()
local_missing=()

# Function to check if a package is installed using dpkg
is_installed_dpkg() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | has_match "install ok installed"
}

# xdg-desktop-portal-hyprland arrives either as a Debian package or as a source build
# (xdph.sh installs the libexec binary to /usr/lib), so accept both shapes.
is_portal_hyprland_backend_installed() {
    if is_installed_dpkg "xdg-desktop-portal-hyprland"; then
        return 0
    fi
    local p
    for p in /usr/lib/xdg-desktop-portal-hyprland \
        /usr/libexec/xdg-desktop-portal-hyprland \
        /usr/local/libexec/xdg-desktop-portal-hyprland; do
        [ -x "$p" ] && return 0
    done
    return 1
}

# xdg-desktop-portal only discovers backends through *.portal descriptor files. Without
# hyprland.portal the backend binary sits unused and screen sharing/screencopy fails,
# which is easy to miss because every file above is present.
is_portal_hyprland_registered() {
    local p
    for p in /usr/share/xdg-desktop-portal/portals/hyprland.portal \
        /usr/local/share/xdg-desktop-portal/portals/hyprland.portal; do
        [ -f "$p" ] && return 0
    done
    return 1
}

# qml6-module-org-hyprland-style has no binary, so a dpkg hit proves nothing about
# usability: Qt resolves QT_QUICK_CONTROLS_STYLE=org.hyprland.style from a QML directory
# that needs a qmldir manifest plus the .qml files. Deleted or half-copied files leave the
# package installed while every themed dialog silently falls back to the default style.
is_qml_hyprland_style_loadable() {
    local dir
    for dir in /usr/lib/*/qt6/qml/org/hyprland/style \
        /usr/local/lib/*/qt6/qml/org/hyprland/style; do
        [ -d "$dir" ] || continue
        [ -f "$dir/qmldir" ] || continue
        compgen -G "$dir/*.qml" >/dev/null && return 0
    done
    return 1
}

# Some entries are file-only at the dpkg level: imagemagick is a metapackage, and the
# polkit agent plus both portal backends install into libexec, outside PATH. For those,
# "installed" still has to be proven by the tool or backend binary the package exists for.
check_package_payload() {
    local candidate
    for candidate in "$@"; do
        case "$candidate" in
        /*)
            if [[ "$candidate" == *'*'* ]]; then
                compgen -G "$candidate" >/dev/null && return 0
            elif [ -x "$candidate" ]; then
                return 0
            fi
            ;;
        *)
            command -v "$candidate" >/dev/null 2>&1 && return 0
            ;;
        esac
    done
    return 1
}

declare -A package_payloads=(
    [imagemagick]="magick convert"
    [polkit-kde-agent-1]="/usr/libexec/polkit-kde-authentication-agent-1 /usr/lib/*/libexec/polkit-kde-authentication-agent-1"
    [xdg-desktop-portal]="/usr/libexec/xdg-desktop-portal /usr/lib/xdg-desktop-portal"
    [xdg-desktop-portal-gtk]="/usr/libexec/xdg-desktop-portal-gtk /usr/lib/xdg-desktop-portal-gtk"
)

# Loop through each package
for pkg in "${packages[@]}"; do
    # Check if the package is installed via dpkg
    if ! is_installed_dpkg "$pkg"; then
        if [ "$pkg" = "yazi" ] && command -v yazi >/dev/null 2>&1; then
            continue
        fi
        if { [ "$pkg" = "libgl-dev" ] || [ "$pkg" = "libgl1-mesa-dev" ] || [ "$pkg" = "mesa-common-dev" ]; } && { is_installed_dpkg "libgl-dev" || is_installed_dpkg "libglvnd-dev" || [ -f /usr/include/GL/gl.h ]; }; then
            continue
        fi
        missing+=("$pkg")
    fi
done

# Check waybar is source-built (not the APT package which lacks Lua support)
if ! is_source_waybar_installed; then
    local_missing+=("waybar (source build)")
fi

# Check required binaries in PATH
for pkg1 in "${required_bins[@]}"; do
    if ! command -v "$pkg1" >/dev/null 2>&1; then
        local_missing+=("$pkg1")
    fi
done

# NetworkManager must be installed, enabled and running: without the daemon there is
# no network/Wi-Fi at all and the waybar network module stays dead. Service state is
# only meaningful on a host running systemd, so chroots/containers are skipped.
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-enabled NetworkManager.service >/dev/null 2>&1; then
        local_missing+=("NetworkManager (service not enabled)")
    elif ! systemctl is-active NetworkManager.service >/dev/null 2>&1; then
        local_missing+=("NetworkManager (service not active)")
    fi
fi

# Portal stack: without a registered Hyprland backend, screen sharing in browsers,
# OBS and screenshot tools that go through the portal silently fail.
if ! is_portal_hyprland_backend_installed; then
    local_missing+=("xdg-desktop-portal-hyprland (backend)")
elif ! is_portal_hyprland_registered; then
    local_missing+=("xdg-desktop-portal-hyprland (hyprland.portal not installed)")
fi

# File-only Qt module: check that Qt can import it instead of trusting dpkg, and name the
# consuming feature so the failure is actionable.
if ! is_qml_hyprland_style_loadable; then
    local_missing+=("qml6-module-org-hyprland-style (org.hyprland.style not loadable)")
fi

# hyprland-qtutils is now only a transitional dummy that hyprland-guiutils
# Breaks/Replaces, so finding it installed means the rename never completed and the
# guiutils tools (hyprland-dialog) are missing beneath it.
if is_installed_dpkg "hyprland-qtutils"; then
    local_missing+=("hyprland-qtutils (obsolete dummy package; install hyprland-guiutils)")
fi

# File-only packages: confirm the payload each one exists for, not just its dpkg entry.
for pkg in "${!package_payloads[@]}"; do
    is_installed_dpkg "$pkg" || continue
    read -r -a candidates <<< "${package_payloads[$pkg]}"
    if ! check_package_payload "${candidates[@]}"; then
        local_missing+=("$pkg (installed but its payload is not usable)")
    fi
done

# Log missing packages
if [ ${#missing[@]} -eq 0 ] && [ ${#local_missing[@]} -eq 0 ]; then
    echo "${OK} GREAT! All ${YELLOW}essential packages${RESET} have been successfully installed." | tee -a "$LOG"
else
    if [ ${#missing[@]} -ne 0 ]; then
        echo "${WARN} The following packages are not installed and will be logged:"
        for pkg in "${missing[@]}"; do
            echo "$pkg"
            echo "$pkg" >>"$LOG" # Log the missing package to the file
        done
    fi

    if [ ${#local_missing[@]} -ne 0 ]; then
        echo "${WARN} The following required components are missing and will be logged:"
        for pkg1 in "${local_missing[@]}"; do
            echo "$pkg1 is missing or not usable"
            echo "$pkg1" >>"$LOG" # Log the missing local package to the file
        done
    fi

    # Add a timestamp when the missing packages were logged
    echo "${NOTE} Missing packages logged at $(date)" >>"$LOG"
fi
