#!/bin/bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hypr Ecosystem #
# hypland-guiutils #

# Dependency note:
# - Qt6 path is used for older hyprland-guiutils tags.
# - Newer tags may switch to a pixman/libdrm/libxkbcommon path upstream.
# If you pin a tag that fails, verify deps against that tag's upstream README.
guiutils=(
	libqt6core5compat6
    qt6-base-dev
	qt6-wayland-dev
    qt6-wayland
	qt6-declarative-dev
	qml6-module-qtcore
	qt6-3d-dev
	qt6-5compat-dev
    libqt6waylandclient6
    qml6-module-qtwayland-client-texturesharing
)

#specific branch or release
tag="v0.2.0"
# Auto-source centralized tags if env is unset
if [ -z "${HYPRLAND_GUIUTILS_TAG:-}" ]; then
  TAGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hypr-tags.env"
  [ -f "$TAGS_FILE" ] && source "$TAGS_FILE"
fi
# Allow environment override
if [ -n "${HYPRLAND_GUIUTILS_TAG:-}" ]; then tag="$HYPRLAND_GUIUTILS_TAG"; fi

tag_compatibility_note() {
    local normalized="${tag#v}"
    if [[ "$(printf '%s\n%s\n' "$normalized" "0.2.0" | sort -V | head -n1)" != "0.2.0" ]]; then
        echo "${WARN} hyprland-guiutils tag ${tag} is older than v0.2.0; Qt6 deps are expected." | tee -a "$LOG"
    else
        echo "${INFO} hyprland-guiutils tag ${tag} is v0.2.0+; if upstream deps moved to pixman path, adjust this script accordingly." | tee -a "$LOG"
    fi
}

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
LOG="Install-Logs/install-$(date +%d-%H%M%S)_hyprland-guiutils.log"
MLOG="install-$(date +%d-%H%M%S)_hyprland-guiutils2.log"
tag_compatibility_note

# Installation of dependencies
printf "\n%s - Installing ${YELLOW}hyprland-guiutils dependencies${RESET} .... \n" "${INFO}"

for PKG1 in "${guiutils[@]}"; do
  re_install_package "$PKG1" 2>&1 | tee -a "$LOG"
  if [ $? -ne 0 ]; then
    echo -e "\e[1A\e[K${ERROR} - ${YELLOW}$PKG1${RESET} Package installation failed, Please check the installation logs"
    exit 1
  fi
done

printf "\n%.0s" {1..1}

# Check if hyprland-guiutils directory exists and remove it (under build/src)
SRC_DIR="$SRC_ROOT/hyprland-guiutils"
if [ -d "$SRC_DIR" ]; then
    rm -rf "$SRC_DIR"
fi

# Clone and build 
printf "${INFO} Installing ${YELLOW}hyprland-guiutils $tag${RESET} ...\n"
if git clone --recursive -b $tag https://github.com/hyprwm/hyprland-guiutils.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1

    BUILD_DIR="$BUILD_ROOT/hyprland-guiutils"
    mkdir -p "$BUILD_DIR"
	cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local -S . -B "$BUILD_DIR" 2>&1 | tee -a "$MLOG"
	cmake --build "$BUILD_DIR" --config Release --target all -j`nproc 2>/dev/null || getconf NPROCESSORS_CONF` 2>&1 | tee -a "$MLOG"
    if [ $DO_INSTALL -eq 1 ]; then
        if sudo cmake --install "$BUILD_DIR" 2>&1 | tee -a "$MLOG" ; then
            printf "${OK} ${MAGENTA}hyprland-guiutils $tag${RESET} installed successfully.\n" 2>&1 | tee -a "$MLOG"
        else
            echo -e "${ERROR} Installation failed for ${YELLOW}hyprland-guiutils $tag${RESET}" 2>&1 | tee -a "$MLOG"
        fi
    else
        echo "${NOTE} DRY RUN: Skipping installation of hyprland-guiutils $tag."
    fi
    #moving the addional logs to Install-Logs directory
    [ -f "$MLOG" ] && mv "$MLOG" "$PARENT_DIR/Install-Logs/"
    cd ..
else
    echo -e "${ERROR} Download failed for ${YELLOW}hyprland-guiutils $tag${RESET}" 2>&1 | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}
