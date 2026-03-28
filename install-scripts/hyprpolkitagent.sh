#!/bin/bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hypr Ecosystem #
# hyprpolkitagent #

polkitagent=(
	libpolkit-agent-1-dev
	libpolkit-qt6-1-dev
  qml6-module-qtquick-layouts
  qt6-tools-dev
  qt6-tools-dev-tools
  qt6-charts-dev
)

#specific branch or release
tag="v0.1.3"

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
MLOG="install-$(date +%d-%H%M%S)_hyprpolkitagent.log"

# Installation of dependencies
printf "\n%s - Installing hyprpolkitagent dependencies.... \n" "${NOTE}"

for PKG1 in "${polkitagent[@]}"; do
  re_install_package "$PKG1" 2>&1 | tee -a "$LOG"
  if [ $? -ne 0 ]; then
    echo -e "\e[1A\e[K${ERROR} - $PKG1 Package installation failed, Please check the installation logs"
    exit 1
  fi
done

# Check if hyprpolkitagent folder exists and remove it (under build/src)
SRC_DIR="$SRC_ROOT/hyprpolkitagent"
if [ -d "$SRC_DIR" ]; then
    printf "${NOTE} Removing existing hyprpolkitagent folder...\n"
    rm -rf "$SRC_DIR"
fi

# Clone and build 
printf "${NOTE} Installing hyprpolkitagent...\n"
if git clone --recursive -b $tag https://github.com/hyprwm/hyprpolkitagent.git "$SRC_DIR"; then
    cd "$SRC_DIR" || exit 1
    BUILD_DIR="$BUILD_ROOT/hyprpolkitagent"
    mkdir -p "$BUILD_DIR"
	cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr -S . -B "$BUILD_DIR"
	cmake --build "$BUILD_DIR" --config Release --target all -j`nproc 2>/dev/null || getconf NPROCESSORS_CONF`
    if sudo cmake --install "$BUILD_DIR" 2>&1 | tee -a "$MLOG" ; then
        printf "${OK} hyprpolkitagent installed successfully.\n" 2>&1 | tee -a "$MLOG"
    else
        echo -e "${ERROR} Installation failed for hyprpolkitagent." 2>&1 | tee -a "$MLOG"
    fi
    #moving the addional logs to Install-Logs directory
    mv $MLOG "$PARENT_DIR/Install-Logs/" || true 
    cd ..
else
    echo -e "${ERROR} Download failed for hyprpolkitagent." 2>&1 | tee -a "$LOG"
fi

printf "\n%.0s" {1..2}

# Install a user-level polkit agent wrapper + systemd unit (best-effort)
USER_BIN="$HOME/.local/bin"
USER_SYSTEMD="$HOME/.config/systemd/user"
WRAPPER="$USER_BIN/polkit-agent"
UNIT="$USER_SYSTEMD/polkit-agent.service"

mkdir -p "$USER_BIN" "$USER_SYSTEMD"

cat >"$WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -u

candidates=(
  "/usr/libexec/polkit-mate-authentication-agent-1"
  "/usr/lib/polkit-mate/polkit-mate-authentication-agent-1"
  "/usr/bin/polkit-mate-authentication-agent-1"
  "/usr/lib/polkit-kde-authentication-agent-1"
  "/usr/libexec/polkit-kde-authentication-agent-1"
  "/usr/bin/polkit-kde-authentication-agent-1"
  "/usr/bin/xfce-polkit"
  "/usr/lib/xfce4/polkit-agent/xfce-polkit"
  "/usr/libexec/xfce-polkit"
  "/usr/libexec/hyprpolkitagent"
  "/usr/lib/hyprpolkitagent"
  "/usr/lib/hyprpolkitagent/hyprpolkitagent"
  "/usr/bin/hyprpolkitagent"
)

for exe in "${candidates[@]}"; do
  if [ -x "$exe" ]; then
    "$exe" &
    pid=$!
    wait "$pid"
    status=$?
    if [ "$status" -eq 0 ]; then
      exit 0
    fi
  fi
done

echo "No supported polkit agent found." >&2
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


