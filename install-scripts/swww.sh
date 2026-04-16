#!/bin/bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# SWWW - Wallpaper Utility #

# specific branch or release (minimum required 0.11.2)
swww_tag="v0.11.2"
swww_min="0.11.2"

# Version compare helper (uses dpkg if available)
version_ge() {
    local a="$1" b="$2"
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --compare-versions "$a" ge "$b"
        return $?
    fi
    [ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | tail -n1)" = "$a" ]
}

# Check if 'swww' is installed and skip if version is sufficient
if command -v swww &>/dev/null; then
    SWWW_VERSION=$(swww --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)
    if [ -n "$SWWW_VERSION" ] && version_ge "$SWWW_VERSION" "$swww_min"; then
        echo -e "${OK} ${MAGENTA}swww ${SWWW_VERSION}${RESET} detected (>= ${swww_min}). Skipping installation."
        exit 0
    else
        echo -e "${INFO} swww ${SWWW_VERSION:-unknown} found; upgrading to ${swww_tag}."
    fi
else
    echo -e "${NOTE} ${MAGENTA}swww${RESET} is not installed. Proceeding with installation."
fi

swww=(
    liblz4-dev
    wayland-protocols
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
LOG="Install-Logs/install-$(date +%d-%H%M%S)_swww.log"
MLOG="install-$(date +%d-%H%M%S)_swww2.log"

# Installation of swww compilation needed
printf "\n%s - Installing ${SKY_BLUE}swww $swww_tag and dependencies${RESET} .... \n" "${NOTE}"

for PKG1 in "${swww[@]}"; do
    install_package "$PKG1" "$LOG"
done
# Ensure wayland.xml is available for build scripts
if [ ! -f /usr/share/wayland-protocols/wayland.xml ] && [ ! -f /usr/local/share/wayland-protocols/wayland.xml ]; then
    echo -e "${WARN} wayland.xml not found; attempting to install wayland-protocols."
    install_package "wayland-protocols" "$LOG"
fi
if [ ! -f /usr/share/wayland-protocols/wayland.xml ] && [ ! -f /usr/local/share/wayland-protocols/wayland.xml ]; then
    echo -e "${WARN} wayland.xml still missing; building wayland-protocols from source."
    if [ -x "$PARENT_DIR/install-scripts/wayland-protocols-src.sh" ]; then
        "$PARENT_DIR/install-scripts/wayland-protocols-src.sh"
    fi
fi

# Export wayland-protocols path so waybackend-scanner can locate wayland.xml
if [ -f /usr/local/share/wayland-protocols/wayland.xml ]; then
    export WAYLAND_PROTOCOLS_DIR=/usr/local/share/wayland-protocols
elif [ -f /usr/share/wayland-protocols/wayland.xml ]; then
    export WAYLAND_PROTOCOLS_DIR=/usr/share/wayland-protocols
fi
if [ -n "${WAYLAND_PROTOCOLS_DIR:-}" ]; then
    export WAYLAND_PROTOCOLS_PATH="${WAYLAND_PROTOCOLS_DIR}"
fi
fi

printf "\n%.0s" {1..2}

# Check if swww directory exists (under build/src)
SRC_DIR="$SRC_ROOT/swww"
if [ -d "$SRC_DIR" ]; then
    cd "$SRC_DIR" || exit 1
    git pull origin main 2>&1 | tee -a "$MLOG"
else
    if git clone --recursive -b $swww_tag https://github.com/LGFae/swww.git "$SRC_DIR"; then
        cd "$SRC_DIR" || exit 1
    else
        echo -e "${ERROR} Download failed for ${YELLOW}swww $swww_tag${RESET}" 2>&1 | tee -a "$LOG"
        exit 1
    fi
fi

# Proceed with the rest of the installation steps
source "$HOME/.cargo/env" || true

cargo build --release 2>&1 | tee -a "$MLOG"

# Checking if swww is previously installed and delete before copying
file1="/usr/bin/swww"
file2="/usr/bin/swww-daemon"

# Check if file1 exists and delete if so
if [ -f "$file1" ]; then
    sudo rm -r "$file1"
fi

# Check if file2 exists and delete if so
if [ -f "$file2" ]; then
    sudo rm -r "$file2"
fi

# Copy binaries to /usr/bin/
sudo cp -r target/release/swww /usr/bin/ 2>&1 | tee -a "$MLOG"
sudo cp -r target/release/swww-daemon /usr/bin/ 2>&1 | tee -a "$MLOG"

# Copy bash completions
sudo mkdir -p /usr/share/bash-completion/completions 2>&1 | tee -a "$MLOG"
sudo cp -r completions/swww.bash /usr/share/bash-completion/completions/swww 2>&1 | tee -a "$MLOG"

# Copy zsh completions
sudo mkdir -p /usr/share/zsh/site-functions 2>&1 | tee -a "$MLOG"
sudo cp -r completions/_swww /usr/share/zsh/site-functions/_swww 2>&1 | tee -a "$MLOG"

# Moving logs into main Install-Logs
mv "$MLOG" "$PARENT_DIR/Install-Logs/" || true
cd - || exit 1

printf "\n%.0s" {1..2}
