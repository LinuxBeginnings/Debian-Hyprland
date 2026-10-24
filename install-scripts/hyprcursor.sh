#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hypr Ecosystem #
# hyprcursor #

cursor=(
libzip-dev
librsvg2-dev
)

#specific branch or release
tag="v0.1.13"
# Auto-source centralized tags if env is unset; allow override via HYPRCURSOR_TAG if present
if [ -z "${HYPRCURSOR_TAG:-}" ]; then
  TAGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hypr-tags.env"
  [ -f "$TAGS_FILE" ] && source "$TAGS_FILE"
fi
if [ -n "${HYPRCURSOR_TAG:-}" ]; then tag="$HYPRCURSOR_TAG"; fi

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || { echo "${ERROR} Failed to change directory to $PARENT_DIR"; exit 1; }

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
  echo "Failed to source Global_functions.sh"
  exit 1
fi

# Dry-run support
DO_INSTALL=1
if [ "$1" = "--dry-run" ] || [ "${DRY_RUN}" = "1" ] || [ "${DRY_RUN}" = "true" ]; then
  DO_INSTALL=0
  echo "${NOTE} DRY RUN: install step will be skipped."
fi

# Prefer source-stack pkg-config metadata first to keep runtime ABI consistent.
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
export CMAKE_PREFIX_PATH="/usr/local:/usr"

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_hyprcursor.log"
MLOG="install-$(date +%d-%H%M%S)_hyprcursor.log"

# Installation of dependencies
printf "\n%s - Installing hyprcursor dependencies.... \n" "${NOTE}"

for PKG1 in "${cursor[@]}"; do
  install_package "$PKG1" 2>&1 | tee -a "$LOG"
  if [ $? -ne 0 ]; then
    echo -e "\e[1A\e[K${ERROR} - $PKG1 Package installation failed, Please check the installation logs"
    exit 1
  fi
done

# Check if hyprcursor folder exists and remove it (under build/src)
SRC_DIR="$SRC_ROOT/hyprcursor"
if [ -d "$SRC_DIR" ]; then
    printf "${NOTE} Removing existing hyprcursor folder...\n"
    rm -rf "$SRC_DIR"
fi

# Clone and build 
printf "${NOTE} Installing hyprcursor...\n"
if git clone --recursive -b $tag https://github.com/hyprwm/hyprcursor.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1
    BUILD_DIR="$BUILD_ROOT/hyprcursor"
    rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
    cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local -S . -B "$BUILD_DIR"
	cmake --build "$BUILD_DIR" --config Release --target all -j`nproc 2>/dev/null || getconf NPROCESSORS_CONF`
    if [ "$DO_INSTALL" -eq 0 ]; then
        echo "${NOTE} DRY RUN: Skipping installation of hyprcursor $tag."
    else
        install_rc=0
        # Do not pipe into tee here: the pipeline status would be tee's status, so a
        # failed install was reported as "installed successfully".
        sudo cmake --install "$BUILD_DIR" > >(tee -a "$MLOG") 2> >(tee -a "$MLOG" >&2) || install_rc=$?
        if [ "$install_rc" -eq 0 ]; then
            printf "${OK} hyprcursor installed successfully.\n" 2>&1 | tee -a "$MLOG"
        else
            echo -e "${ERROR} Installation failed for hyprcursor (exit ${install_rc})." 2>&1 | tee -a "$MLOG"
            INSTALL_FAILED=1
        fi
    fi
    #moving the addional logs to Install-Logs directory
    mv $MLOG "$PARENT_DIR/Install-Logs/" || true 
    cd ..
else
    echo -e "${ERROR} Download failed for hyprcursor." 2>&1 | tee -a "$LOG"
    exit 1
fi

# Surface a failed install step instead of reporting a false success.
if [ "${INSTALL_FAILED:-0}" -ne 0 ]; then
    echo -e "${ERROR} hyprcursor install step failed; see Install-Logs/" | tee -a "$LOG"
    exit 1
fi

printf "\n%.0s" {1..2}


