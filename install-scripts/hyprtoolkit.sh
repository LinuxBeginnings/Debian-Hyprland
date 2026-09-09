#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hypr Ecosystem #
# hyprtoolkit #
hyprtoolkit_deps=(
)

#specific branch or release (fallback)
tag_default="main"
# Auto-source centralized tags if env is unset
if [ -z "${HYPRTOOLKIT_TAG:-}" ]; then
  TAGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hypr-tags.env"
  [ -f "$TAGS_FILE" ] && source "$TAGS_FILE"
fi
TAG_SRC="${HYPRTOOLKIT_TAG:-$tag_default}"
[[ "$TAG_SRC" =~ ^(auto|latest|head|HEAD)$ ]] && git_ref="" || git_ref="$TAG_SRC"

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

# Ensure toolchain paths prefer /usr/local
export PATH="/usr/local/bin:${PATH}"
if [[ ":${PKG_CONFIG_PATH:-}:" != *":/usr/local/share/pkgconfig:"* ]]; then
  export PKG_CONFIG_PATH="/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}"
fi
if [[ ":${PKG_CONFIG_PATH}:" != *":/usr/local/lib/pkgconfig:"* ]]; then
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH}"
fi
export CMAKE_PREFIX_PATH="/usr/local:${CMAKE_PREFIX_PATH:-}"

# Set the name of the log file to include the current date and time
LOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_hyprtoolkit.log"
MLOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_hyprtoolkit2.log"

printf "\n%s - Installing ${YELLOW}hyprtoolkit dependencies${RESET} .... \n" "${INFO}"
for PKG1 in "${hyprtoolkit_deps[@]}"; do
  re_install_package "$PKG1" 2>&1 | tee -a "$LOG"
  if [ $? -ne 0 ]; then
    echo -e "\e[1A\e[K${ERROR} - ${YELLOW}$PKG1${RESET} Package installation failed, Please check the installation logs"
    exit 1
  fi
done
printf "\n%.0s" {1..1}

# Clone, build, and install using Cmake
printf "${INFO} Installing ${YELLOW}hyprtoolkit ${git_ref:-default-branch}${RESET} ...\n"

# Check if hyprtoolkit folder exists and remove it (under build/src)
SRC_DIR="$SRC_ROOT/hyprtoolkit"
if [ -d "$SRC_DIR" ]; then
  printf "${NOTE} Removing existing hyprtoolkit folder...\n"
  rm -rf "$SRC_DIR" >> "$LOG" 2>&1
fi
if git clone --recursive ${git_ref:+-b "$git_ref"} "https://github.com/hyprwm/hyprtoolkit.git" "$SRC_DIR" >> "$LOG" 2>&1; then
  cd "$SRC_DIR" || exit 1
  printf "${NOTE} Applying hyprtoolkit format fix...\n"
  python3 - <<'PY' >> "$LOG" 2>&1
import re, pathlib
path = pathlib.Path("src/system/Icons.cpp")
if path.is_file():
    text = path.read_text()
    text = re.sub(
        r'g_logger->log\(HT_LOG_TRACE,\s*"CSystemIconFactory:\s*Found\s*\{\}\s*as\s*default\s*fallback",\s*themeDir\.value\(\)\);',
        'g_logger->log(HT_LOG_TRACE, "CSystemIconFactory: Found default fallback theme");',
        text,
    )
    text = re.sub(
        r'g_logger->log\(HT_LOG_TRACE,\s*"CSystemIconFactory:\s*parsing\s*inherited\s*theme\s*\{\}",\s*\*inheritTheme\);',
        'g_logger->log(HT_LOG_TRACE, "CSystemIconFactory: parsing inherited theme");',
        text,
    )
    path.write_text(text)
PY
  BUILD_DIR="$BUILD_ROOT/hyprtoolkit"
  rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
  if ! cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local -S . -B "$BUILD_DIR" >> "$MLOG" 2>&1; then
    echo -e "${ERROR} CMake configure failed for hyprtoolkit. See: $MLOG" | tee -a "$MLOG"
    exit 1
  fi
  if ! cmake --build "$BUILD_DIR" --config Release --target all -j"$(nproc 2>/dev/null || getconf _NPROCESSORS_CONF)" >> "$MLOG" 2>&1; then
    echo -e "${ERROR} Build failed for hyprtoolkit. See: $MLOG" | tee -a "$MLOG"
    exit 1
  fi
  if [ $DO_INSTALL -eq 1 ]; then
    if sudo cmake --install "$BUILD_DIR" >> "$MLOG" 2>&1; then
      printf "${OK} hyprtoolkit installed successfully.\n" 2>&1 | tee -a "$MLOG"
    else
      echo -e "${ERROR} Installation failed for hyprtoolkit." 2>&1 | tee -a "$MLOG"
      exit 1
    fi
  else
    echo "${NOTE} DRY RUN: Skipping installation of hyprtoolkit $tag." | tee -a "$MLOG"
  fi
  cd ..
else
  echo -e "${ERROR} Download failed for hyprtoolkit" 2>&1 | tee -a "$LOG"
  exit 1
fi

printf "\n%.0s" {1..2}

