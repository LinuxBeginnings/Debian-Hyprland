#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hypr Ecosystem #
# hyprwayland-scanner #

scan_depend=(
    libpugixml-dev
    wayland
    libwayland-bin
    libexpat1-dev
    libffi-dev
)

#specific branch or release
tag="v0.4.5"
# Auto-source centralized tags if env is unset
if [ -z "${HYPRWAYLAND_SCANNER_TAG:-}" ]; then
  TAGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hypr-tags.env"
  [ -f "$TAGS_FILE" ] && source "$TAGS_FILE"
fi
# Allow environment override
if [ -n "${HYPRWAYLAND_SCANNER_TAG:-}" ]; then tag="$HYPRWAYLAND_SCANNER_TAG"; fi

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
LOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_hyprwayland-scanner.log"
MLOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_hyprwayland-scanner2.log"

##
# Installation of dependencies
printf "\n%s - Installing hyprwayland-scanner dependencies.... \n" "${NOTE}"

for PKG1 in "${scan_depend[@]}"; do
  install_package "$PKG1" 2>&1 | tee -a "$LOG"
  if [ $? -ne 0 ]; then
    echo -e "\e[1A\e[K${ERROR} - $PKG1 Package installation failed, Please check the installation logs"
    exit 1
  fi
done

get_wayland_scanner_version() {
  local ver=""
  ver="$(pkg-config --modversion wayland-scanner 2>/dev/null || true)"
  if [ -z "$ver" ] && command -v wayland-scanner >/dev/null 2>&1; then
    ver="$(wayland-scanner --version 2>/dev/null | awk '{print $NF}' || true)"
  fi
  printf "%s" "$ver"
}

bootstrap_wayland_scanner() {
  local wtag="${WAYLAND_SCANNER_BOOTSTRAP_TAG:-1.25.0}"
  local repo="https://gitlab.freedesktop.org/wayland/wayland.git"
  local wsrc="$SRC_ROOT/wayland"
  local wbuild="$BUILD_ROOT/wayland"

  printf "${NOTE} Bootstrapping ${YELLOW}wayland-scanner${RESET} from Wayland ${YELLOW}${wtag}${RESET} ...\n" | tee -a "$LOG"

  [ -d "$wsrc" ] && rm -rf "$wsrc"
  if ! git clone --depth=1 --filter=blob:none "$repo" "$wsrc" >>"$LOG" 2>&1; then
    echo "${ERROR} Failed to clone Wayland source for scanner bootstrap." | tee -a "$LOG"
    return 1
  fi

  cd "$wsrc" || return 1
  git fetch --tags --depth=1 >/dev/null 2>&1 || true
  local checked_out=0
  local candidate
  for candidate in "$wtag" "v$wtag"; do
    if git rev-parse -q --verify "refs/tags/$candidate" >/dev/null; then
      git checkout -q "refs/tags/$candidate" >>"$LOG" 2>&1
      checked_out=1
      break
    fi
  done
  if [ "$checked_out" -ne 1 ]; then
    echo "${ERROR} Wayland tag $wtag not found in $repo" | tee -a "$LOG"
    return 1
  fi

  rm -rf "$wbuild" && mkdir -p "$wbuild"
  if ! meson setup "$wbuild" --prefix=/usr/local -Ddocumentation=false -Dtests=false >>"$LOG" 2>&1; then
    echo "${ERROR} Failed meson setup for Wayland scanner bootstrap." | tee -a "$LOG"
    return 1
  fi
  if ! meson compile -C "$wbuild" -j"$(nproc 2>/dev/null || getconf _NPROCESSORS_CONF)" >>"$LOG" 2>&1; then
    echo "${ERROR} Failed compiling Wayland scanner bootstrap." | tee -a "$LOG"
    return 1
  fi

  if [ "$DO_INSTALL" -eq 1 ]; then
    if ! sudo meson install -C "$wbuild" >>"$LOG" 2>&1; then
      echo "${ERROR} Failed installing Wayland scanner bootstrap." | tee -a "$LOG"
      return 1
    fi
  else
    local stagedir="$wbuild/stage"
    local staged_pc_paths="$stagedir/usr/local/lib/pkgconfig:$stagedir/usr/local/share/pkgconfig"
    local multiarch=""
    rm -rf "$stagedir" && mkdir -p "$stagedir"
    if ! meson install -C "$wbuild" --destdir "$stagedir" >>"$LOG" 2>&1; then
      echo "${ERROR} Failed staging Wayland scanner bootstrap for dry run." | tee -a "$LOG"
      return 1
    fi
    if command -v dpkg-architecture >/dev/null 2>&1; then
      multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
    fi
    if [ -n "$multiarch" ] && [ -d "$stagedir/usr/local/lib/$multiarch/pkgconfig" ]; then
      staged_pc_paths="$stagedir/usr/local/lib/$multiarch/pkgconfig:$staged_pc_paths"
    fi
    export PATH="$stagedir/usr/local/bin:${PATH}"
    export PKG_CONFIG_PATH="$staged_pc_paths:${PKG_CONFIG_PATH:-}"
    echo "${NOTE} DRY RUN: using staged wayland-scanner from $stagedir/usr/local/bin" | tee -a "$LOG"
  fi

  cd "$PARENT_DIR" || return 1
  return 0
}

need_wayland_scanner_bootstrap=0
if [ -n "${WAYLAND_PROTOCOLS_TAG:-}" ] && [ "$(printf '%s\n' "1.49" "${WAYLAND_PROTOCOLS_TAG}" | sort -V | head -n1)" = "1.49" ]; then
  need_wayland_scanner_bootstrap=1
fi
if [ "$need_wayland_scanner_bootstrap" -eq 1 ]; then
  have_wayland_scanner_ver="$(get_wayland_scanner_version)"
  if [ -z "$have_wayland_scanner_ver" ] || [ "$(printf '%s\n' "1.25.0" "$have_wayland_scanner_ver" | sort -V | head -n1)" != "1.25.0" ]; then
    echo "${WARN} wayland-scanner ${have_wayland_scanner_ver:-unknown} is too old for wayland-protocols ${WAYLAND_PROTOCOLS_TAG} (requires >= 1.25.0)." | tee -a "$LOG"
    bootstrap_wayland_scanner || exit 1
  fi
fi

printf "${NOTE} Installing hyprwayland-scanner...\n"  

# Check if hyprwayland-scanner folder exists and remove it (under build/src)
SRC_DIR="$SRC_ROOT/hyprwayland-scanner"
if [ -d "$SRC_DIR" ]; then
    printf "${NOTE} Removing existing hyprwayland-scanner folder...\n"
    rm -rf "$SRC_DIR"
fi

# Clone and build hyprlang
printf "${NOTE} Installing hyprwayland-scanner...\n"
if git clone --recursive -b $tag https://github.com/hyprwm/hyprwayland-scanner.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1
    BUILD_DIR="$BUILD_ROOT/hyprwayland-scanner"
    rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
	cmake -DCMAKE_INSTALL_PREFIX=/usr -B "$BUILD_DIR"
	cmake --build "$BUILD_DIR" -j `nproc`
    if [ $DO_INSTALL -eq 1 ]; then
        if sudo cmake --install "$BUILD_DIR" 2>&1 | tee -a "$MLOG" ; then
            printf "${OK} hyprwayland-scanner installed successfully.\n" 2>&1 | tee -a "$MLOG"
        else
            echo -e "${ERROR} Installation failed for hyprwayland-scanner." 2>&1 | tee -a "$MLOG"
        fi
    else
        echo "${NOTE} DRY RUN: Skipping installation of hyprwayland-scanner $tag."
    fi
    #moving the addional logs to Install-Logs directory
    [ -f "$MLOG" ] || true
    cd ..
else
    echo -e "${ERROR} Download failed for hyprwayland-scanner. Please check log." 2>&1 | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}

