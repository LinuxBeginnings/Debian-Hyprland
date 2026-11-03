#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Global Functions for Scripts #

set -e
# errtrace: without it the ERR trap below is not inherited by shell functions, and all
# of a module script's work happens inside functions.
set -E

# `set -e` stops a module at the first failing command; without a trap the log simply
# ends, with no hint about which command died. Print the failing command and its line
# so a silent abort (e.g. a producer killed by SIGPIPE) can be diagnosed.
report_unexpected_failure() {
  local rc="$1" line="$2" cmd="$3" fn="${4:-main}" where
  # With errtrace the trap also fires inside command substitutions and again for the
  # enclosing function call; the parent shell reports the full command, so skip the
  # subshell copy to avoid printing the same failure twice.
  if [ "${BASH_SUBSHELL:-0}" -gt 0 ]; then
    return 0
  fi
  where="$0:$line"
  if [ -n "$fn" ] && [ "$fn" != "main" ]; then
    where="$where (in $fn)"
  fi
  printf '\n%s Aborting: command exited with status %s\n' "${ERROR:-[ERROR]}" "$rc" >&2
  printf '%s   command : %s\n' "${ERROR:-[ERROR]}" "$cmd" >&2
  printf '%s   location: %s\n' "${ERROR:-[ERROR]}" "$where" >&2
  if [ -n "${LOG:-}" ]; then
    # Grouped so a shell error from the redirect itself (unwritable LOG) stays quiet.
    {
      printf '\n[ERROR] Aborting: command exited with status %s\n[ERROR]   command : %s\n[ERROR]   location: %s\n' \
        "$rc" "$cmd" "$where" >>"$LOG"
    } 2>/dev/null || true
  fi
  return 0
}
trap 'report_unexpected_failure "$?" "$LINENO" "$BASH_COMMAND" "${FUNCNAME[0]:-main}"' ERR

# Set some colors for output messages.
# - Escapes are only emitted when stdout is a terminal, so piped output and log files
#   stay plain text.
# - A single reset (`\e[0m`) replaces `tput sgr0`, which also emits ESC(B, a charset
#   switch that survives as a literal "^[(B" in logs and captured output.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  OK=$'\e[32m[OK]\e[0m'
  ERROR=$'\e[31m[ERROR]\e[0m'
  NOTE=$'\e[33m[NOTE]\e[0m'
  INFO=$'\e[34m[INFO]\e[0m'
  WARN=$'\e[31m[WARN]\e[0m'
  CAT=$'\e[36m[ACTION]\e[0m'
  MAGENTA=$'\e[35m'
  ORANGE=$'\e[38;5;214m'
  WARNING=$'\e[31m'
  YELLOW=$'\e[33m'
  GREEN=$'\e[32m'
  BLUE=$'\e[34m'
  SKY_BLUE=$'\e[36m'
  RESET=$'\e[0m'
else
  OK="[OK]"; ERROR="[ERROR]"; NOTE="[NOTE]"; INFO="[INFO]"; WARN="[WARN]"; CAT="[ACTION]"
  MAGENTA=""; ORANGE=""; WARNING=""; YELLOW=""; GREEN=""; BLUE=""; SKY_BLUE=""; RESET=""
fi

# `grep -q` exits as soon as it matches, which can kill a streaming producer with SIGPIPE
# (141) and, under `set -o pipefail`, abort the run. `grep -c` reads its input to EOF and
# reports the same 0/1 status, so package checks use it and discard the count.
has_match() { grep -c "$@" >/dev/null; }

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
  # Ensure standard paths are always present in PATH
  for p in /usr/local/bin /usr/local/sbin /usr/bin /bin /usr/sbin /sbin; do
    case ":${PATH:-}:" in
      *":${p}:"*) ;;
      *) export PATH="${PATH:+$PATH:}${p}" ;;
    esac
  done
  export PATH="/usr/local/bin:${PATH}"

  local multiarch=""
  if command -v dpkg-architecture >/dev/null 2>&1; then
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
  fi

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

    tput civis 2>/dev/null || true
    printf "\r${INFO} Installing ${YELLOW}%s${RESET} ..." "$package_name"

    while ps -p $pid &> /dev/null; do
        printf "\r${INFO} Installing ${YELLOW}%s${RESET} %s" "$package_name" "${spin_chars[i]}"
        i=$(( (i + 1) % 10 ))  
        sleep 0.3  
    done

    printf "\r${INFO} Installing ${YELLOW}%s${RESET} ... Done!%-20s \n\n" "$package_name" ""
    tput cnorm 2>/dev/null || true
}


# Function for version comparison (returns 0 if $1 >= $2)
version_ge() {
  local a="$1" b="$2"
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --compare-versions "$a" ge "$b"
    return $?
  fi
  # Fallback: returns 0 if a >= b
  [ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | tail -n1)" = "$a" ]
}

# Function for installing packages with a progress bar
install_package() { 
  # A dry run must not touch the package database. Modules that only compile still call
  # this for their build dependencies, so skip the apt step and report success.
  if [ "${DRY_RUN:-0}" = "1" ] || [ "${DRY_RUN:-}" = "true" ]; then
    echo -e "${INFO} DRY RUN: skipping install of ${MAGENTA}$1${RESET}"
    return 0
  fi
  if dpkg-query -W -f='${Status}' "$1" 2>/dev/null | has_match "ok installed" ; then
    echo -e "${INFO} ${MAGENTA}$1${RESET} is already installed. Skipping..."
  else 
    (
      stdbuf -oL sudo apt install -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$1" 
    
    # Double check if the package successfully installed
    if dpkg-query -W -f='${Status}' "$1" 2>/dev/null | has_match "ok installed"; then
        echo -e "\e[1A\e[K${OK} Package ${YELLOW}$1${RESET} has been successfully installed!"
    else
        echo -e "\e[1A\e[K${ERROR} ${YELLOW}$1${RESET} failed to install. Please check the install.log. You may need to install it manually. Sorry, I have tried :("
    fi
  fi
}
# Function for installing packages from a target release (e.g., backports)
target_release_available_for_pkg() {
  local pkg="$1"
  local target="$2"
  apt-cache policy "$pkg" 2>/dev/null | has_match -E "[[:space:]]${target}/"
}
install_package_target() {
  local pkg="$1"
  local target="$2"
  if dpkg -l | has_match -w "$pkg" ; then
    echo -e "${INFO} ${MAGENTA}$pkg${RESET} is already installed. Skipping..."
  else
    if ! target_release_available_for_pkg "$pkg" "$target"; then
      echo -e "${WARN} ${YELLOW}$pkg${RESET} is not available in target '${MAGENTA}$target${RESET}'. Falling back to default suite."
      install_package "$pkg"
      return
    fi
    (
      stdbuf -oL sudo apt install -y -t "$target" "$pkg" 2>&1
    ) >> "$LOG" 2>&1 &
    PID=$!
    show_progress $PID "$pkg"

    # Double check if the package successfully installed
    if dpkg -l | has_match -w "$pkg"; then
      echo -e "\e[1A\e[K${OK} Package ${YELLOW}$pkg${RESET} has been successfully installed!"
    else
      echo -e "\e[1A\e[K${ERROR} ${YELLOW}$pkg${RESET} failed to install. Please check the install.log. You may need to install it manually. Sorry, I have tried :("
    fi
  fi
}

# Function for build depencies with a progress bar
build_dep() { 
  if [ "${DRY_RUN:-0}" = "1" ] || [ "${DRY_RUN:-}" = "true" ]; then
    echo -e "${INFO} DRY RUN: skipping build-dep for ${MAGENTA}$1${RESET}"
    return 0
  fi
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
    # A dry run only compiles, so it must not reinstall anything from apt either.
    if [ "${DRY_RUN:-0}" = "1" ] || [ "${DRY_RUN:-}" = "true" ]; then
        echo -e "${INFO} DRY RUN: skipping re-install of ${MAGENTA}$1${RESET}"
        return 0
    fi
    (
        stdbuf -oL sudo apt install --reinstall -y "$1" 2>&1
    ) >> "$LOG" 2>&1 &
    
    PID=$!
    show_progress $PID "$1" 
    
    if dpkg-query -W -f='${Status}' "$1" 2>/dev/null | has_match "ok installed"; then
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
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | has_match "ok installed" ; then
    echo -e "${NOTE} removing $pkg ..."
    sudo apt autoremove -y "$1" >> "$LOG" 2>&1 | grep -v "error: target not found"
    
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | has_match "ok installed" ; then
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