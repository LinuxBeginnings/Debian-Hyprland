#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# AWWW - Wallpaper Utility (swww successor) #

awww_deps=(
    liblz4-dev
    libwayland-dev
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
# Source paths now that Global_functions defines SRC_ROOT
awww_repo="https://codeberg.org/LGFae/awww"
awww_src_dir="$SRC_ROOT/awww"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_awww.log"
MLOG="install-$(date +%d-%H%M%S)_awww2.log"

# Installation of awww compilation needed
printf "\n%s - Installing ${SKY_BLUE}awww and dependencies${RESET} .... \n" "${NOTE}"

for PKG1 in "${awww_deps[@]}"; do
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

printf "\n%.0s" {1..2}

# Check if awww directory exists (under build/src)
if [ -d "$awww_src_dir" ]; then
    cd "$awww_src_dir" || exit 1
    git pull 2>&1 | tee -a "$MLOG"
else
    if git clone --recursive "$awww_repo" "$awww_src_dir"; then
        cd "$awww_src_dir" || exit 1
    else
        echo -e "${ERROR} Download failed for ${YELLOW}awww${RESET}" 2>&1 | tee -a "$LOG"
        exit 1
    fi
fi

# Proceed with the rest of the installation steps
source "$HOME/.cargo/env" || true

cargo build --release 2>&1 | tee -a "$MLOG"

# Remove old swww/awww binaries before copying
remove_bins=(
    /usr/bin/swww
    /usr/bin/swww-daemon
    /usr/local/bin/swww
    /usr/local/bin/swww-daemon
    /usr/bin/awww
    /usr/bin/awww-daemon
    /usr/local/bin/awww
    /usr/local/bin/awww-daemon
)
for bin in "${remove_bins[@]}"; do
    if [ -e "$bin" ]; then
        sudo rm -f "$bin"
    fi
done

# Copy binaries to /usr/bin/
sudo cp -r target/release/awww /usr/bin/ 2>&1 | tee -a "$MLOG"
sudo cp -r target/release/awww-daemon /usr/bin/ 2>&1 | tee -a "$MLOG"

# Moving logs into main Install-Logs
mv "$MLOG" "$PARENT_DIR/Install-Logs/" || true
cd - || exit 1

printf "\n%.0s" {1..2}
