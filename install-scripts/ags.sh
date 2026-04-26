#!/bin/bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Aylur's GTK Shell #

ags=(
    npm 
    meson 
    libgjs-dev 
    gjs 
    gobject-introspection
    libgirepository1.0-dev
    gir1.2-gtk-4.0
    gir1.2-gtklayershell-0.1
    libgtk-layer-shell-dev 
    libgtk-3-dev
    libadwaita-1-dev
    libpam0g-dev 
    libpulse-dev 
    libdbusmenu-gtk3-dev 
    libsoup-3.0-dev
    ninja-build
    build-essential
    pkg-config
)


build_dep=(
    pam
)

# specific tags to download
ags_tag="v1.9.0"

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
LOG="Install-Logs/install-$(date +%d-%H%M%S)_ags.log"
MLOG="install-$(date +%d-%H%M%S)_ags2.log"

# Check if AGS is installed
if command -v ags &>/dev/null; then
    AGS_VERSION=$(ags -v | awk '{print $NF}')
    if [[ "$AGS_VERSION" == "1.9.0" ]]; then
        printf "${INFO} ${MAGENTA}Aylur's GTK Shell v1.9.0${RESET} is already installed.\n"
        read -r -p "Reinstall v1.9.0 anyway? [y/N]: " REPLY
        case "$REPLY" in
          [yY]|[yY][eE][sS])
            printf "${NOTE} Reinstalling Aylur's GTK Shell v1.9.0...\n"
            ;;
          *)
            printf "Skipping reinstallation.\n"
            printf "\n%.0s" {1..2}
            exit 0
            ;;
        esac
    fi
fi

# Installation of main components
printf "\n%s - Installing ${SKY_BLUE}Aylur's GTK shell $ags_tag${RESET} Dependencies \n" "${INFO}"

# Installing ags Dependencies
for PKG1 in "${ags[@]}"; do
  install_package "$PKG1" "$LOG"
done

if command -v npm >/dev/null 2>&1; then
  npm_version="$(npm --version 2>/dev/null || true)"
  if [ -n "$npm_version" ]; then
    printf "${INFO} npm detected (v%s). Skipping reinstall.\\n" "$npm_version"
  else
    printf "${INFO} npm detected. Skipping reinstall.\\n"
  fi
else
  install_package "npm" "$LOG"
fi

printf "\n%.0s" {1..1}

for PKG1 in "${build_dep[@]}"; do
  build_dep "$PKG1" "$LOG"
done

# install typescript by npm if tsc is missing or too old
needs_tsc_install=0
if command -v tsc >/dev/null 2>&1; then
  tsc_version="$(tsc --version 2>/dev/null | awk '{print $2}')"
  if [ -n "$tsc_version" ]; then
    # ags >= 1.9 requires TypeScript >= 5.0 for 'const' type modifiers
    major_ver="$(echo "$tsc_version" | cut -d. -f1 | grep -oE '^[0-9]+' || echo 0)"
    if [ "$major_ver" -lt 5 ]; then
      printf "${INFO} TypeScript compiler detected (v%s) but is too old (needs >= 5). Proceeding with install.\\n" "$tsc_version"
      needs_tsc_install=1
    else
      printf "${INFO} TypeScript compiler detected (v%s). Skipping global install.\\n" "$tsc_version"
    fi
  else
    printf "${INFO} TypeScript compiler detected. Skipping global install.\\n"
  fi
else
  needs_tsc_install=1
fi

if [ "$needs_tsc_install" -eq 1 ]; then
  # Purge older apt version if present to avoid conflicts
  if dpkg -l | grep -q "^ii  node-typescript"; then
    printf "${INFO} Removing old apt package node-typescript...\\n"
    sudo apt-get purge -y node-typescript 2>&1 | tee -a "$LOG"
  fi
  sudo npm install --global --prefix /usr/local typescript 2>&1 | tee -a "$LOG"
fi

# ags v1
printf "${NOTE} Install and Compiling ${SKY_BLUE}Aylur's GTK shell $ags_tag${RESET}..\n"

# Remove previous sources (both legacy "ags" and tagged "ags_v1.9.0") under build/src
for OLD in "ags" "ags_v1.9.0"; do
    SRC_DIR="$SRC_ROOT/$OLD"
    if [ -d "$SRC_DIR" ]; then
        printf "${NOTE} Removing existing %s directory...\\n" "$SRC_DIR"
        rm -rf "$SRC_DIR"
    fi
done

printf "\n%.0s" {1..1}
printf "${INFO} Kindly Standby...cloning and compiling ${SKY_BLUE}Aylur's GTK shell $ags_tag${RESET}...\n"
printf "\n%.0s" {1..1}
# Clone repository with the specified tag and capture git output into MLOG
SRC_DIR="$SRC_ROOT/ags_v1.9.0"
if git clone --depth=1 https://github.com/LinuxBeginnings/ags_v1.9.0.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1
    BUILD_DIR="$BUILD_ROOT/ags_v1.9.0"
    rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
    npm install
    if [ -f "$SRC_DIR/tsconfig.json" ] && [ -f "$SRC_DIR/src/meson.build" ]; then
      mkdir -p "$SRC_DIR/types"
      cat >"$SRC_DIR/types/gi-any.d.ts" <<'EOF'
declare module 'gi://Gtk?version=3.0' { import Gtk from '@girs/gtk-3.0'; export default Gtk; }
declare module 'gi://Gdk?version=3.0' { import Gdk from '@girs/gdk-3.0'; export default Gdk; }
declare module 'gi://GdkPixbuf' { import GdkPixbuf from '@girs/gdkpixbuf-2.0'; export default GdkPixbuf; }
declare module 'gi://Gio' { import Gio from '@girs/gio-2.0'; export default Gio; }
declare module 'gi://GLib?version=2.0' { import GLib from '@girs/glib-2.0'; export default GLib; }
declare module 'gi://GObject' { import GObject from '@girs/gobject-2.0'; export default GObject; }
declare module 'gi://Gvc' { import Gvc from '@girs/gvc-1.0'; export default Gvc; }
declare module 'gi://NM' { import NM from '@girs/nm-1.0'; export default NM; }
declare module 'gi://Notify' { import Notify from '@girs/notify-0.7'; export default Notify; }
declare module 'gi://Soup?version=3.0' { import Soup from '@girs/soup-3.0'; export default Soup; }
declare module 'gi://DbusmenuGtk3' { import DbusmenuGtk3 from '@girs/dbusmenugtk3-0.4'; export default DbusmenuGtk3; }
declare module 'gi://Pango' { import Pango from '@girs/pango-1.0'; export default Pango; }
declare module 'gi://cairo?version=1.0' { import Cairo from '@girs/cairo-1.0'; export default Cairo; }
declare function logError(...args: any[]): void;
EOF
      if ! grep -q '"rootDir"' "$SRC_DIR/tsconfig.json"; then
        sed -i '/"baseUrl":/i\        "rootDir": "src",' "$SRC_DIR/tsconfig.json"
      fi
      if ! grep -q '"noImplicitAny"' "$SRC_DIR/tsconfig.json"; then
        sed -i '/"strict":/a\        "noImplicitAny": false,' "$SRC_DIR/tsconfig.json"
      fi
      if ! grep -q '\"noEmitOnError\"' "$SRC_DIR/tsconfig.json"; then
        sed -i '/\"strict\":/a\        \"noEmitOnError\": false,' "$SRC_DIR/tsconfig.json"
      fi
      if ! grep -q '"ignoreDeprecations"' "$SRC_DIR/tsconfig.json"; then
        sed -i '/"moduleResolution":/a\        "ignoreDeprecations": "6.0",' "$SRC_DIR/tsconfig.json"
      fi
      python3 - <<'PY'
from pathlib import Path

path = Path("src/meson.build")
text = path.read_text()
old_variants = [
    "command: [ tsc, '--outDir', tsc_out ],",
    "command: [ 'bash', '-lc', 'tsc -p \"' + (meson.project_source_root() / 'tsconfig.json').to_string() + '\" --outDir \"' + tsc_out.to_string() + '\" --noEmitOnError false || true' ],",
    "command: [ 'bash', '-lc', 'tsc -p \"${MESON_SOURCE_ROOT}/tsconfig.json\" --outDir \"${MESON_BUILD_ROOT}/tsc-out\" --noEmitOnError false || true' ],",
]
new = "command: [ 'bash', '-lc', 'tsc -p \"' + meson.project_source_root() + '/tsconfig.json\" --outDir \"' + meson.project_build_root() + '/tsc-out\" --noEmitOnError false || true' ],"
for old in old_variants:
    if old in text:
        text = text.replace(old, new)
path.write_text(text)
PY
    fi
    meson setup "$BUILD_DIR"
    sudo meson install -C "$BUILD_DIR" 2>&1 | tee -a "$MLOG"
    meson_status=${PIPESTATUS[0]}
   if [ "$meson_status" -eq 0 ]; then
    printf "\n${OK} ${YELLOW}Aylur's GTK shell $ags_tag${RESET} installed successfully.\n" 2>&1 | tee -a "$MLOG"

    # Patch installed AGS launchers to ensure GI typelibs in /usr/local/lib are discoverable in GJS ESM
    printf "${NOTE} Applying AGS launcher patch for GI typelibs search path...\n"

    patch_ags_launcher() {
      local target="$1"
      if ! sudo test -f "$target"; then
        return 1
      fi

      # 1) Remove deprecated GIR Repository path tweaks and GIRepository import (harmless if absent)
      sudo sed -i \
        -e '/Repository\.prepend_search_path/d' \
        -e '/Repository\.prepend_library_path/d' \
        -e '/gi:\/\/GIRepository/d' \
        "$target"

      # 2) Ensure GLib import exists (insert after first import line, or at top if none)
      if ! sudo grep -q '^import GLib from "gi://GLib";' "$target"; then
        TMPF=$(sudo mktemp)
        sudo awk 'BEGIN{added=0} {
          if (!added && $0 ~ /^import /) { print; print "import GLib from \"gi://GLib\";"; added=1; next }
          print
        } END { if (!added) print "import GLib from \"gi://GLib\";" }' "$target" | sudo tee "$TMPF" >/dev/null
        sudo mv "$TMPF" "$target"
      fi

      # 3) Inject GI_TYPELIB_PATH export right after the GLib import (once)
      if ! sudo grep -q 'GLib.setenv("GI_TYPELIB_PATH"' "$target"; then
        TMPF=$(sudo mktemp)
        sudo awk '{print} $0 ~ /^import GLib from "gi:\/\/GLib";$/ {print "const __old = GLib.getenv(\"GI_TYPELIB_PATH\");"; print "GLib.setenv(\"GI_TYPELIB_PATH\", \"/usr/local/lib/x86_64-linux-gnu:/usr/local/lib64:/usr/local/lib:/usr/local/lib64/girepository-1.0:/usr/local/lib/girepository-1.0:/usr/local/lib/x86_64-linux-gnu/girepository-1.0:/usr/lib/x86_64-linux-gnu/girepository-1.0:/usr/lib/girepository-1.0:/usr/lib/ags:/usr/local/lib/ags:/usr/lib64/ags\" + (__old ? \":\" + __old : \"\"), true);"; print "const __oldld = GLib.getenv(\"LD_LIBRARY_PATH\");"; print "GLib.setenv(\"LD_LIBRARY_PATH\", \"/usr/local/lib/x86_64-linux-gnu:/usr/local/lib64:/usr/local/lib\" + (__oldld ? \":\" + __oldld : \"\"), true);"}' "$target" | sudo tee "$TMPF" >/dev/null
        sudo mv "$TMPF" "$target"
      fi

      # 4) Ensure LD_LIBRARY_PATH export exists even if GI_TYPELIB_PATH was already present
      if ! sudo grep -q 'GLib.setenv("LD_LIBRARY_PATH"' "$target"; then
        TMPF=$(sudo mktemp)
        sudo awk '{print} $0 ~ /^import GLib from "gi:\/\/GLib";$/ {print "const __oldld = GLib.getenv(\"LD_LIBRARY_PATH\");"; print "GLib.setenv(\"LD_LIBRARY_PATH\", \"/usr/local/lib64:/usr/local/lib\" + (__oldld ? \":\" + __oldld : \"\"), true);"}' "$target" | sudo tee "$TMPF" >/dev/null
        sudo mv "$TMPF" "$target"
      fi

      # Restore executable bit for bin wrappers (mv from mktemp resets mode to 0600)
      case "$target" in
        */bin/ags)
          sudo chmod 0755 "$target" || true
          ;;
      esac

      printf "${OK} Patched: %s\n" "$target"
      return 0
    }

    # Try common locations
    for CAND in \
      "/usr/local/share/com.github.Aylur.ags/com.github.Aylur.ags" \
      "/usr/share/com.github.Aylur.ags/com.github.Aylur.ags" \
      "/usr/local/bin/ags" \
      "/usr/bin/ags"; do
      patch_ags_launcher "$CAND" || true
    done

    # Create an env-setting wrapper for AGS to ensure GI typelibs/libs are discoverable
    printf "${NOTE} Creating env wrapper /usr/local/bin/ags...\n"
    sudo tee /usr/local/bin/ags >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
cd "$HOME" 2>/dev/null || true
# Locate AGS ESM entry
MAIN_JS="/usr/local/share/com.github.Aylur.ags/com.github.Aylur.ags"
if [ ! -f "$MAIN_JS" ]; then
  MAIN_JS="/usr/share/com.github.Aylur.ags/com.github.Aylur.ags"
fi
if [ ! -f "$MAIN_JS" ]; then
  echo "Unable to find AGS entry script (com.github.Aylur.ags) in /usr/local/share or /usr/share" >&2
  exit 1
fi
# Ensure GI typelibs and native libs are discoverable before gjs ESM loads
export GI_TYPELIB_PATH="/usr/local/lib/x86_64-linux-gnu:/usr/local/lib64:/usr/local/lib:/usr/local/lib64/girepository-1.0:/usr/local/lib/girepository-1.0:/usr/local/lib/x86_64-linux-gnu/girepository-1.0:/usr/lib/x86_64-linux-gnu/girepository-1.0:/usr/lib/girepository-1.0:/usr/lib64/girepository-1.0:/usr/lib/ags:/usr/local/lib/ags:/usr/lib64/ags:${GI_TYPELIB_PATH-}"
export LD_LIBRARY_PATH="/usr/local/lib/x86_64-linux-gnu:/usr/local/lib64:/usr/local/lib:${LD_LIBRARY_PATH-}"
exec /usr/bin/gjs -m "$MAIN_JS" "$@"
WRAP
    sudo chmod 0755 /usr/local/bin/ags
    # Ensure ESM entry is readable by gjs
    sudo chmod 0644 /usr/local/share/com.github.Aylur.ags/com.github.Aylur.ags 2>/dev/null || true
    sudo chmod 0644 /usr/share/com.github.Aylur.ags/com.github.Aylur.ags 2>/dev/null || true
    printf "${OK} AGS wrapper installed at /usr/local/bin/ags\n"
  else
    echo -e "\n${ERROR} ${YELLOW}Aylur's GTK shell $ags_tag${RESET} Installation failed\n " 2>&1 | tee -a "$MLOG"
   fi
    # Move logs to Install-Logs directory
    mv "$MLOG" "$PARENT_DIR/Install-Logs/" || true
    cd ..
else
    echo -e "\n${ERROR} Failed to download ${YELLOW}Aylur's GTK shell $ags_tag${RESET} Please check your connection\n" 2>&1 | tee -a "$LOG"
    mv "$MLOG" "$PARENT_DIR/Install-Logs/" || true
    exit 1
fi

printf "\n%.0s" {1..2}
