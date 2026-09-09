#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hypr Ecosystem #
# hyprpolkitagent #

# Build-time dependencies for hyprpolkitagent
polkitagent=(
    libsdbus-c++-dev
    libdrm-dev
    libpixman-1-dev
    libpolkit-agent-1-dev
    libpolkit-qt6-1-dev
    mate-polkit
    policykit-1-gnome
)

# specific branch or release (fallback)
tag_default="v0.2.0"
if [ -z "${HYPRPOLKITAGENT_TAG:-}" ]; then
  TAGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hypr-tags.env"
  [ -f "$TAGS_FILE" ] && source "$TAGS_FILE"
fi
TAG_SRC="${HYPRPOLKITAGENT_TAG:-$tag_default}"
[[ "$TAG_SRC" =~ ^(auto|latest)$ ]] && git_ref="" || git_ref="$TAG_SRC"

DO_INSTALL=1
[ "$1" = "--dry-run" ] || [ "${DRY_RUN}" = "1" ] || [ "${DRY_RUN}" = "true" ] && { DO_INSTALL=0; echo "${NOTE} DRY RUN: install step will be skipped."; }

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
LOG="Install-Logs/install-$(date +%d-%H%M%S)_hyprpolkitagent.log"
MLOG="install-$(date +%d-%H%M%S)_hyprpolkitagent2.log"

# Installation of dependencies
printf "\n%s - Installing ${YELLOW}hyprpolkitagent dependencies${RESET} .... \n" "${INFO}"

for PKG1 in "${polkitagent[@]}"; do
  re_install_package "$PKG1" 2>&1 | tee -a "$LOG"
done

# Ensure toolchain paths prefer /usr/local
export PATH="/usr/local/bin:${PATH}"
if [[ ":${PKG_CONFIG_PATH:-}:" != *":/usr/local/share/pkgconfig:"* ]]; then
  export PKG_CONFIG_PATH="/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}"
fi
if [[ ":${PKG_CONFIG_PATH}:" != *":/usr/local/lib/pkgconfig:"* ]]; then
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH}"
fi
export CMAKE_PREFIX_PATH="/usr/local:${CMAKE_PREFIX_PATH:-}"

# Ensure required hypr* libs are installed (hyprlang, hyprutils, hyprgraphics, hyprtoolkit)
need_lang=0; need_utils=0; need_graphics=0; need_toolkit=0
pkg-config --exists hyprlang || need_lang=1
pkg-config --exists hyprutils || need_utils=1
pkg-config --exists hyprgraphics || need_graphics=1
pkg-config --exists hyprtoolkit || need_toolkit=1

if [ $need_lang -eq 1 ] && [ -x "$PARENT_DIR/install-scripts/hyprlang.sh" ]; then
  echo "${NOTE} Installing missing hyprlang..."; "$PARENT_DIR/install-scripts/hyprlang.sh"
fi
if [ $need_utils -eq 1 ] && [ -x "$PARENT_DIR/install-scripts/hyprutils.sh" ]; then
  echo "${NOTE} Installing missing hyprutils..."; "$PARENT_DIR/install-scripts/hyprutils.sh"
fi
if [ $need_graphics -eq 1 ] && [ -x "$PARENT_DIR/install-scripts/hyprgraphics.sh" ]; then
  echo "${NOTE} Installing missing hyprgraphics..."; "$PARENT_DIR/install-scripts/hyprgraphics.sh"
fi
if [ $need_toolkit -eq 1 ] && [ -x "$PARENT_DIR/install-scripts/hyprtoolkit.sh" ]; then
  echo "${NOTE} Installing missing hyprtoolkit..."; "$PARENT_DIR/install-scripts/hyprtoolkit.sh"
fi

# Check if hyprpolkitagent folder exists and remove it (under build/src)
SRC_DIR="$SRC_ROOT/hyprpolkitagent"
rm -rf "$SRC_DIR" 2>/dev/null || true

# Clone and build 
printf "${INFO} Installing ${YELLOW}hyprpolkitagent ${git_ref:-default-branch}${RESET} ...\n"
if git clone --recursive ${git_ref:+-b "$git_ref"} https://github.com/hyprwm/hyprpolkitagent.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1
    BUILD_DIR="$BUILD_ROOT/hyprpolkitagent"
    rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
    cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local -S . -B "$BUILD_DIR"
    cmake --build "$BUILD_DIR" --config Release --target all -j`nproc 2>/dev/null || getconf _NPROCESSORS_CONF`
    if [ $DO_INSTALL -eq 1 ]; then
        if sudo cmake --install "$BUILD_DIR" 2>&1 | tee -a "$MLOG" ; then
            printf "${OK} ${MAGENTA}hyprpolkitagent ${git_ref:-default}${RESET} installed successfully.\n" 2>&1 | tee -a "$MLOG"
        else
            echo -e "${ERROR} Installation failed for ${YELLOW}hyprpolkitagent ${git_ref:-default}${RESET}" 2>&1 | tee -a "$MLOG"
        fi
    else
        echo "${NOTE} DRY RUN: Skipping installation of hyprpolkitagent." | tee -a "$MLOG"
    fi
    # moving the additional logs to Install-Logs directory
    [ -f "$MLOG" ] && mv "$MLOG" "$PARENT_DIR/Install-Logs/" || true 
    cd ..
else
    echo -e "${ERROR} Download failed for ${YELLOW}hyprpolkitagent ${git_ref:-default-branch}${RESET}" 2>&1 | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}

if [ $DO_INSTALL -eq 1 ]; then
    # Install a user-level polkit agent wrapper + systemd unit (best-effort)
    USER_BIN="$HOME/.local/bin"
    USER_SYSTEMD="$HOME/.config/systemd/user"
    WRAPPER="$USER_BIN/polkit-agent"
    UNIT="$USER_SYSTEMD/polkit-agent.service"

    mkdir -p "$USER_BIN" "$USER_SYSTEMD"

    cat >"$WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -u

LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/polkit-agent.log"
mkdir -p "$(dirname "$LOG_FILE")"
echo "[$(date -Is)] starting polkit-agent wrapper" >>"$LOG_FILE"
if pgrep -u "$UID" -f 'polkit-mate-authentication-agent-1|polkit-gnome-authentication-agent-1|polkit-kde-authentication-agent-1|xfce-polkit' >/dev/null 2>&1; then
  echo "[$(date -Is)] agent already running, exiting" >>"$LOG_FILE"
  exit 0
fi
if pgrep -u "$UID" -f 'hyprpolkitagent' >/dev/null 2>&1; then
  echo "[$(date -Is)] hyprpolkitagent running, replacing it" >>"$LOG_FILE"
  pkill -u "$UID" -f 'hyprpolkitagent' || true
fi

candidates=(
  "/usr/local/libexec/hyprpolkitagent"
  "/usr/local/bin/hyprpolkitagent"
  "/usr/libexec/hyprpolkitagent"
  "/usr/bin/hyprpolkitagent"
  "/usr/lib/hyprpolkitagent/hyprpolkitagent"
  "/usr/lib/hyprpolkitagent"
  "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
  "/usr/libexec/polkit-gnome-authentication-agent-1"
  "/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1"
  "/usr/libexec/polkit-mate-authentication-agent-1"
  "/usr/lib/polkit-mate/polkit-mate-authentication-agent-1"
  "/usr/bin/polkit-mate-authentication-agent-1"
  "/usr/lib/polkit-kde-authentication-agent-1"
  "/usr/libexec/polkit-kde-authentication-agent-1"
  "/usr/bin/polkit-kde-authentication-agent-1"
  "/usr/bin/xfce-polkit"
  "/usr/lib/xfce4/polkit-agent/xfce-polkit"
  "/usr/libexec/xfce-polkit"
)

for exe in "${candidates[@]}"; do
  if [ -x "$exe" ]; then
    echo "[$(date -Is)] trying: $exe" >>"$LOG_FILE"
    "$exe" &
    pid=$!
    wait "$pid"
    status=$?
    echo "[$(date -Is)] exit: $exe status=$status" >>"$LOG_FILE"
    if [ "$status" -eq 0 ]; then
      exit 0
    fi
  fi
done

echo "No supported polkit agent found." >&2
echo "[$(date -Is)] no supported polkit agent found" >>"$LOG_FILE"
exit 1
EOF

    chmod +x "$WRAPPER"

    cat >"$UNIT" <<EOF
[Unit]
Description=Polkit authentication agent
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=QT_QPA_PLATFORM=wayland
Environment=GDK_BACKEND=wayland
Environment=XDG_CURRENT_DESKTOP=Hyprland
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 50); do [ -n "\$WAYLAND_DISPLAY" ] && [ -n "\$XDG_RUNTIME_DIR" ] && [ -S "\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY" ] && exit 0; sleep 0.2; done; exit 1'
ExecStart=$WRAPPER
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target
EOF

    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      systemctl --user enable --now polkit-agent.service >/dev/null 2>&1 || true
    fi
fi


