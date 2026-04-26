#!/bin/bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Build and install RE2 from source (for libabsl ABI compatibility)

#specific branch or release (optional)
RE2_TAG="${RE2_TAG:-}"

# Dry-run support
DO_INSTALL=1
if [ "$1" = "--dry-run" ] || [ "${DRY_RUN}" = "1" ] || [ "${DRY_RUN}" = "true" ]; then
    DO_INSTALL=0
    echo "${NOTE} DRY RUN: install step will be skipped."
fi

FORCE_RE2=0
if [ "$1" = "--force" ] || [ "$2" = "--force" ]; then
    FORCE_RE2=1
fi

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || exit 1

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

LOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_re2.log"

if [ $FORCE_RE2 -eq 0 ] && [ -f /usr/local/lib/libre2.so ]; then
    echo "${INFO} /usr/local/lib/libre2.so already present. Use --force to rebuild." | tee -a "$LOG"
    exit 0
fi

SRC_DIR="$SRC_ROOT/re2"
BUILD_DIR="$BUILD_ROOT/re2"

rm -rf "$SRC_DIR" "$BUILD_DIR" 2>/dev/null || true

printf "${NOTE} Cloning and Installing ${YELLOW}RE2${RESET} ${RE2_TAG:+($RE2_TAG)} ...\\n" | tee -a "$LOG"
if git clone --depth=1 ${RE2_TAG:+-b "$RE2_TAG"} https://github.com/google/re2.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1
    mkdir -p "$BUILD_DIR"
    cmake -S . -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DRE2_BUILD_TESTING=OFF
    cmake --build "$BUILD_DIR" -j "$(nproc 2>/dev/null || getconf _NPROCESSORS_CONF)" | tee -a "$LOG"
    if [ $DO_INSTALL -eq 1 ]; then
        if sudo cmake --install "$BUILD_DIR" 2>&1 | tee -a "$LOG"; then
            sudo ldconfig || true
            echo "${OK} RE2 installed successfully." | tee -a "$LOG"
        else
            echo "${ERROR} RE2 installation failed." | tee -a "$LOG"
            exit 1
        fi
    else
        echo "${NOTE} DRY RUN: Skipping installation of RE2." | tee -a "$LOG"
    fi
else
    echo "${ERROR} Download failed for RE2." | tee -a "$LOG"
    exit 1
fi
