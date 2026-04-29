#!/usr/bin/env bash

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (e.g., sudo $0)" >&2
  exit 1
fi

cat >/etc/apt/sources.list.d/debian-debug.list <<'EOF'
deb http://deb.debian.org/debian-debug testing-debug main
EOF

apt-get update

apt-get install -y \
  gdb \
  systemd-coredump \
  elfutils \
  debuginfod \
  strace \
  ltrace \
  linux-perf \
  valgrind \
  xwayland-dbgsym \
  xserver-xorg-core-dbgsym \
  hyprland-dbgsym \
  libwlroots-0.19-dbgsym \
  xdg-desktop-portal-hyprland-dbgsym \
  libwayland-client0-dbgsym \
  libwayland-server0-dbgsym \
  libwayland-egl1-dbgsym \
  libwayland-cursor0-dbgsym \
  libinput10-dbgsym \
  libgl1-mesa-dri-dbgsym \
  mesa-vulkan-drivers-dbgsym \
  libdrm2-dbgsym \
  libgbm1-dbgsym \
  libx11-6-dbgsym \
  libxcb1-dbgsym \
  libxkbcommon0-dbgsym
