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
    yazi
    zoxide
    libopengl-dev
    libglvnd-dev
    libgl-dev
    libglx-dev
)

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
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

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
        echo "${WARN} The following required binaries are missing from PATH and will be logged:"
        for pkg1 in "${local_missing[@]}"; do
            echo "$pkg1 is not installed. can't find it in PATH"
            echo "$pkg1" >>"$LOG" # Log the missing local package to the file
        done
    fi

    # Add a timestamp when the missing packages were logged
    echo "${NOTE} Missing packages logged at $(date)" >>"$LOG"
fi
