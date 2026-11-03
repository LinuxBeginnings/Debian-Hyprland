#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# https://github.com/LinuxBeginnings

# Set some colors for output messages.
# - Escapes are only emitted when stdout is a terminal, so piped output and log files
#   stay plain text.
# - A single reset (`\e[0m`) replaces `tput sgr0`, which also emits ESC(B, a charset
#   switch that survives as a literal "^[(B" in logs and captured output.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    OK=$'\e[32m[OK]\e[0m'
    ERROR=$'\e[31m[ERROR]\e[0m'
    NOTE=$'\e[33m[NOTE]\e[0m'
    INFO=$'\e[34m[INFO]\e[0m'
    WARN=$'\e[31m[WARN]\e[0m'
    CAT=$'\e[36m[ACTION]\e[0m'
    MAGENTA=$'\e[35m'
    ORANGE=$'\e[38;5;214m'
    WARNING=$'\e[31m'
    YELLOW=$'\e[33m'
    GREEN=$'\e[32m'
    BLUE=$'\e[34m'
    SKY_BLUE=$'\e[36m'
    RESET=$'\e[0m'
else
    OK="[OK]"; ERROR="[ERROR]"; NOTE="[NOTE]"; INFO="[INFO]"; WARN="[WARN]"; CAT="[ACTION]"
    MAGENTA=""; ORANGE=""; WARNING=""; YELLOW=""; GREEN=""; BLUE=""; SKY_BLUE=""; RESET=""
fi

# Variables
Distro="Debian-Hyprland"
Github_URL="https://github.com/LinuxBeginnings/$Distro.git"
Distro_DIR="$HOME/$Distro"

printf "\n%.0s" {1..1}

if ! command -v git &>/dev/null; then
    echo "${INFO} Git not found! ${SKY_BLUE}Installing Git...${RESET}"
    if ! sudo apt install -y git; then
        echo "${ERROR} Failed to install Git. Exiting."
        exit 1
    fi
fi

printf "\n%.0s" {1..1}

if [ -d "$Distro_DIR" ]; then
    echo "${YELLOW}$Distro_DIR exists. Removing and performing a fresh clone... ${RESET}"
    rm -rf "$Distro_DIR"
    git clone --depth=1 "$Github_URL" "$Distro_DIR"
    cd "$Distro_DIR"
    chmod +x install.sh
    ./install.sh
else
    echo "${MAGENTA}$Distro_DIR does not exist. Cloning the repository...${RESET}"
    git clone --depth=1 "$Github_URL" "$Distro_DIR"
    cd "$Distro_DIR"
    chmod +x install.sh
    ./install.sh
fi

