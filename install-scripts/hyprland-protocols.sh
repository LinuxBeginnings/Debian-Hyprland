#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hypr Ecosystem #
# hypland-protocols #


# Build-time dependencies
build_deps=(
    cmake
    pkgconf
    git
)

# specific branch or release (fallback)
tag_default="v0.7.1"
# Auto-source centralized tags if env is unset
if [ -z "${HYPRLAND_PROTOCOLS_TAG:-}" ]; then
  TAGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hypr-tags.env"
  [ -f "$TAGS_FILE" ] && source "$TAGS_FILE"
fi
TAG_SRC="${HYPRLAND_PROTOCOLS_TAG:-$tag_default}"
# Respect auto/latest by not forcing a branch/tag
if [[ "$TAG_SRC" =~ ^(auto|latest)$ ]]; then
  git_ref=""
else
  git_ref="$TAG_SRC"
fi

# Dry-run support
DO_INSTALL=1
if [ "$1" = "--dry-run" ] || [ "${DRY_RUN}" = "1" ] || [ "${DRY_RUN}" = "true" ]; then
    DO_INSTALL=0
    echo "${NOTE} DRY RUN: install step will be skipped."
fi

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

# Set the name of the log file to include the current date and time
LOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_hyprland-protocols.log"
MLOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_hyprland-protocols2.log"

# Installation of dependencies
printf "\n%s - Installing ${YELLOW}hyprland-protocols dependencies${RESET} .... \n" "${INFO}"
for PKG in "${build_deps[@]}"; do
    install_package "$PKG" "$LOG"
done

# Check if hyprland-protocols directory exists and remove it (under build/src)
SRC_DIR="$SRC_ROOT/hyprland-protocols"
if [ -d "$SRC_DIR" ]; then
    rm -rf "$SRC_DIR"
fi

# Clone and build 
printf "${INFO} Installing ${YELLOW}hyprland-protocols ${git_ref:-default-branch}${RESET} ...\n"
if git clone --recursive ${git_ref:+-b "$git_ref"} https://github.com/hyprwm/hyprland-protocols.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1
    BUILD_DIR="$BUILD_ROOT/hyprland-protocols"
    rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

    if [ -f CMakeLists.txt ]; then
        cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local -S . -B "$BUILD_DIR" 2>&1 | tee -a "$MLOG"
        cmake --build "$BUILD_DIR" --config Release --target all -j"$(nproc 2>/dev/null || getconf _NPROCESSORS_CONF)" 2>&1 | tee -a "$MLOG"
        if [ $DO_INSTALL -eq 1 ]; then
            if sudo cmake --install "$BUILD_DIR" 2>&1 | tee -a "$MLOG"; then
                printf "${OK} ${MAGENTA}hyprland-protocols ${git_ref:-default}${RESET} installed successfully.\n" 2>&1 | tee -a "$MLOG"
            else
                echo -e "${ERROR} Installation failed for ${YELLOW}hyprland-protocols ${git_ref:-default}${RESET}" 2>&1 | tee -a "$MLOG"
                exit 1
            fi
        else
            echo "${NOTE} DRY RUN: Skipping installation of hyprland-protocols ${git_ref:-default}."
        fi
    elif [ -f meson.build ]; then
        meson setup "$BUILD_DIR" --prefix=/usr/local 2>&1 | tee -a "$MLOG"
        meson compile -C "$BUILD_DIR" -j"$(nproc 2>/dev/null || getconf _NPROCESSORS_CONF)" 2>&1 | tee -a "$MLOG"
        if [ $DO_INSTALL -eq 1 ]; then
            if sudo meson install -C "$BUILD_DIR" 2>&1 | tee -a "$MLOG"; then
                printf "${OK} ${MAGENTA}hyprland-protocols ${git_ref:-default}${RESET} installed successfully.\n" 2>&1 | tee -a "$MLOG"
            else
                echo -e "${ERROR} Installation failed for ${YELLOW}hyprland-protocols ${git_ref:-default}${RESET}" 2>&1 | tee -a "$MLOG"
                exit 1
            fi
        else
            echo "${NOTE} DRY RUN: Skipping installation of hyprland-protocols ${git_ref:-default}."
        fi
    else
        echo -e "${ERROR} No CMakeLists.txt or meson.build found in hyprland-protocols" 2>&1 | tee -a "$LOG"
        exit 1
    fi
    cd "$PARENT_DIR" || exit 1
else
    echo -e "${ERROR} Download failed for ${YELLOW}hyprland-protocols ${git_ref:-default}${RESET}" 2>&1 | tee -a "$LOG"
    exit 1
fi

printf "\n%.0s" {1..2}
