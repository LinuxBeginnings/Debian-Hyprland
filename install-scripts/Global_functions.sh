#!/bin/bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Global Functions for Scripts #

set -e

# Set some colors for output messages (be resilient in non-interactive shells)
if tput sgr0 >/dev/null 2>&1; then
  OK="$(tput setaf 2)[OK]$(tput sgr0)"
  ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
  NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
  INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
  WARN="$(tput setaf 1)[WARN]$(tput sgr0)"
  CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
  MAGENTA="$(tput setaf 5)"
  ORANGE="$(tput setaf 214)"
  WARNING="$(tput setaf 1)"
  YELLOW="$(tput setaf 3)"
  GREEN="$(tput setaf 2)"
  BLUE="$(tput setaf 4)"
  SKY_BLUE="$(tput setaf 6)"
  RESET="$(tput sgr0)"
else
  OK="[OK]"; ERROR="[ERROR]"; NOTE="[NOTE]"; INFO="[INFO]"; WARN="[WARN]"; CAT="[ACTION]"
  MAGENTA=""; ORANGE=""; WARNING=""; YELLOW=""; GREEN=""; BLUE=""; SKY_BLUE=""; RESET=""
fi

# Create Directory for Install Logs
if [ ! -d Install-Logs ]; then
    mkdir Install-Logs
fi

# Shared build output root (override with BUILD_ROOT env)
BUILD_ROOT="${BUILD_ROOT:-$PWD/build}"
mkdir -p "$BUILD_ROOT"
SRC_ROOT="${SRC_ROOT:-$BUILD_ROOT/src}"
mkdir -p "$SRC_ROOT"

# Prefer /usr/local headers/libs/tools for source-built Hypr* components.
# This reduces accidental linkage against distro-packaged /usr artifacts.
setup_usr_local_env() {
  local multiarch=""
  if command -v dpkg-architecture >/dev/null 2>&1; then
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  fi

  export PATH="/usr/local/bin:${PATH}"

  local local_pc="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig"
  if [ -n "$multiarch" ]; then
    local_pc="/usr/local/lib/${multiarch}/pkgconfig:${local_pc}"
  fi
  export PKG_CONFIG_PATH="${local_pc}:${PKG_CONFIG_PATH:-}"

  export CMAKE_PREFIX_PATH="/usr/local:${CMAKE_PREFIX_PATH:-}"
  export CPPFLAGS="-I/usr/local/include ${CPPFLAGS:-}"
  export LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib -Wl,-rpath-link,/usr/local/lib ${LDFLAGS:-}"
  export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
}

setup_usr_local_env

# Show progress function
show_progress() {
    local pid=$1
    local package_name=$2
    local spin_chars=("●○○○○○○○○○" "○●○○○○○○○○" "○○●○○○○○○○" "○○○●○○○○○○" "○○○○●○○○○" \
                      "○○○○○●○○○○" "○○○○○○●○○○" "○○○○○○○●○○" "○○○○○○○○●○" "○○○○○○○○○●") 
    local i=0

    tput civis 
    printf "\r${INFO} Installing ${YELLOW}%s${RESET} ..." "$package_name"

    while ps -p $pid &> /dev/null; do
        printf "\r${INFO} Installing ${YELLOW}%s${RESET} %s" "$package_name" "${spin_chars[i]}"
        i=$(( (i + 1) % 10 ))  
        sleep 0.3  
    done

    printf "\r${INFO} Installing ${YELLOW}%s${RESET} ... Done!%-20s \n\n" "$package_name" ""
    tput cnorm  
}


# Function for installing packages with a progress bar
install_package() { 
  if dpkg -l | grep -q -w "$1" ; then
    echo -e "${INFO} ${MAGENTA}$1${RESET} is already installed. Skipping..."
  else 
    (
      stdbuf -oL sudo apt install -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1" 
    
    # Double check if the package successfully installed
    if dpkg -l | grep -q -w "$1"; then
        echo -e "\e[1A\e[K${OK} Package ${YELLOW}$1${RESET} has been successfully installed!"
    else
        echo -e "\e[1A\e[K${ERROR} ${YELLOW}$1${RESET} failed to install. Please check the install.log. You may need to install it manually. Sorry, I have tried :("
    fi
  fi
}
# Function for installing packages from a target release (e.g., backports)
install_package_target() {
  local pkg="$1"
  local target="$2"
  if dpkg -l | grep -q -w "$pkg" ; then
    echo -e "${INFO} ${MAGENTA}$pkg${RESET} is already installed. Skipping..."
  else
    (
      stdbuf -oL sudo apt install -y -t "$target" "$pkg" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$pkg"

    # Double check if the package successfully installed
    if dpkg -l | grep -q -w "$pkg"; then
      echo -e "\e[1A\e[K${OK} Package ${YELLOW}$pkg${RESET} has been successfully installed!"
    else
      echo -e "\e[1A\e[K${ERROR} ${YELLOW}$pkg${RESET} failed to install. Please check the install.log. You may need to install it manually. Sorry, I have tried :("
    fi
  fi
}

# Function for build depencies with a progress bar
build_dep() { 
  echo -e "${INFO} building dependencies for ${MAGENTA}$1${RESET} "
    (
      stdbuf -oL sudo apt build-dep -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1" 
}

# Function for cargo install with a progress bar
cargo_install() { 
  echo -e "${INFO} installing ${MAGENTA}$1${RESET} using cargo..."
    (
      stdbuf -oL cargo install "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1" 
}

# Function for re-installing packages with a progress bar
re_install_package() {
    (
        stdbuf -oL sudo apt install --reinstall -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    
    PID=$!
    show_progress $PID "$1" 
    
    if dpkg -l | grep -q -w "$1"; then
        echo -e "\e[1A\e[K${OK} Package ${YELLOW}$1${RESET} has been successfully re-installed!"
    else
        # Package not found, reinstallation failed
        echo -e "${ERROR} ${YELLOW}$1${RESET} failed to re-install. Please check the install.log. You may need to install it manually. Sorry, I have tried :("
    fi
}

# Function for removing packages
uninstall_package() {
  local pkg="$1"

  # Checking if package is installed
  if sudo dpkg -l | grep -q -w "^ii  $1" ; then
    echo -e "${NOTE} removing $pkg ..."
    sudo apt autoremove -y "$1" >> "$LOG" 2>&1 | grep -v "error: target not found"
    
    if ! dpkg -l | grep -q -w "^ii  $1" ; then
      echo -e "\e[1A\e[K${OK} ${MAGENTA}$1${RESET} removed."
    else
      echo -e "\e[1A\e[K${ERROR} $pkg Removal failed. No actions required."
      return 1
    fi
  else
    echo -e "${INFO} Package $pkg not installed, skipping."
  fi
  return 0
}