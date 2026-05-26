#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Yazi file manager install #

YAZI_KEY_URL="https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc"
YAZI_KEY_PATH="/etc/apt/trusted.gpg.d/debian.griffo.io.gpg"
YAZI_REPO_FILE="/etc/apt/sources.list.d/yazi.list"
YAZI_DISTRO="$(lsb_release -sc 2>/dev/null || echo stable)"
YAZI_REPO_LINE="deb [signed-by=${YAZI_KEY_PATH}] https://debian.griffo.io/apt ${YAZI_DISTRO} main"

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
LOG="Install-Logs/install-$(date +%d-%H%M%S)_yazi.log"

configure_yazi_repo() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY-RUN] sudo wget -qO- $YAZI_KEY_URL | sudo gpg --dearmor --yes -o $YAZI_KEY_PATH" | tee -a "$LOG"
        echo "[DRY-RUN] echo \"$YAZI_REPO_LINE\" | sudo tee $YAZI_REPO_FILE" | tee -a "$LOG"
        echo "[DRY-RUN] sudo apt update" | tee -a "$LOG"
        return 0
    fi

    echo "${INFO} Configuring ${YELLOW}Yazi${RESET} APT repository..." | tee -a "$LOG"
    sudo wget -qO- "$YAZI_KEY_URL" | sudo gpg --dearmor --yes -o "$YAZI_KEY_PATH" 2>&1 | tee -a "$LOG"

    if [ -f "$YAZI_REPO_FILE" ] && grep -Fxq "$YAZI_REPO_LINE" "$YAZI_REPO_FILE"; then
        echo "${INFO} Yazi apt source already configured." | tee -a "$LOG"
    else
        printf '%s\n' "$YAZI_REPO_LINE" | sudo tee "$YAZI_REPO_FILE" >/dev/null
        echo "${OK} Added Yazi apt source to ${YAZI_REPO_FILE}." | tee -a "$LOG"
    fi

    sudo apt update 2>&1 | tee -a "$LOG"
}

install_yazi_package() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY-RUN] sudo apt-get -s install -y yazi" | tee -a "$LOG"
        sudo apt-get -s install -y yazi >/dev/null || true
        return 0
    fi
    install_package "yazi" "$LOG"
}

printf "\n%s - Installing ${SKY_BLUE}Yazi file manager${RESET}...\n" "${NOTE}"
configure_yazi_repo
install_yazi_package
printf "\n%.0s" {1..1}
