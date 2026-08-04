#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# Dry-run orchestrator for Hyprland and companion modules
# - Compiles components but skips installation (uses DRY_RUN=1)
# - Summarizes PASS/FAIL per module to Install-Logs/
#
# Usage:
#   chmod +x ./dry-run-build.sh
#   ./dry-run-build.sh                  # run full stack dry-run
#   ./dry-run-build.sh --with-deps      # install dependencies first, then dry-run build
#   ./dry-run-build.sh --only hyprland  # run a subset (comma-separated allowed)
#   ./dry-run-build.sh --skip qtutils   # skip one or more (comma-separated)
#   ./dry-run-build.sh --check          # detect and report install method per module (no build)
#
# Notes:
# - Run from the repository root. Do not cd into install-scripts/.
# - You can also call modules directly, e.g., DRY_RUN=1 ./install-scripts/hyprland.sh

set -u
set -o pipefail

REPO_ROOT=$(pwd)
LOG_DIR="$REPO_ROOT/Install-Logs"
mkdir -p "$LOG_DIR"
TS=$(date +%F-%H%M%S)
SUMMARY_LOG="$LOG_DIR/build-dry-run-$TS.log"

# Default module order (core first, then Hyprland)
DEFAULT_MODULES=(
  hyprutils
  hyprlang
  hyprcursor
  aquamarine
  hyprgraphics
  hyprtoolkit
  hyprwayland-scanner
  wayland-protocols-src
  hyprland-protocols
  hyprland-qt-support
  hyprland-qtutils
  hyprland
  hyprshutdown
)

WITH_DEPS=0
ONLY_LIST=""
SKIP_LIST=""
CHECK_ONLY=0

usage() {
  grep '^# ' "$0" | sed 's/^# \{0,1\}//'
}

# Detect whether a module is installed via apt packages, source (/usr/local),
# both, or not at all.  Echoes: apt | source | both | none
detect_module_method() {
  local mod="$1"
  local is_apt=0 is_source=0
  case "$mod" in
    hyprutils)
      dpkg -l 'libhyprutils*' 2>/dev/null | grep -q '^ii' && is_apt=1
      ls /usr/local/lib/libhyprutils.so* 2>/dev/null | grep -q . && is_source=1 ;;
    hyprlang)
      dpkg -l 'libhyprlang*' 2>/dev/null | grep -q '^ii' && is_apt=1
      ls /usr/local/lib/libhyprlang.so* 2>/dev/null | grep -q . && is_source=1 ;;
    hyprcursor)
      dpkg -l 'libhyprcursor*' 2>/dev/null | grep -q '^ii' && is_apt=1
      ls /usr/local/lib/libhyprcursor.so* 2>/dev/null | grep -q . && is_source=1 ;;
    aquamarine)
      dpkg -l 'libaquamarine*' 2>/dev/null | grep -q '^ii' && is_apt=1
      ls /usr/local/lib/libaquamarine.so* 2>/dev/null | grep -q . && is_source=1 ;;
    hyprgraphics)
      dpkg -l 'libhyprgraphics*' 2>/dev/null | grep -q '^ii' && is_apt=1
      ls /usr/local/lib/libhyprgraphics.so* 2>/dev/null | grep -q . && is_source=1 ;;
    hyprtoolkit)
      dpkg -l 'hyprtoolkit' 2>/dev/null | grep -q '^ii' && is_apt=1
      { [ -f /usr/local/lib/pkgconfig/hyprtoolkit.pc ] || \
        [ -f /usr/local/share/pkgconfig/hyprtoolkit.pc ]; } && is_source=1 ;;
    hyprwayland-scanner)
      dpkg -l 'hyprwayland-scanner' 2>/dev/null | grep -q '^ii' && is_apt=1
      [ -f /usr/local/bin/hyprwayland-scanner ] && is_source=1 ;;
    wayland-protocols-src)
      dpkg -l 'wayland-protocols' 2>/dev/null | grep -q '^ii' && is_apt=1
      [ -f /usr/local/share/pkgconfig/wayland-protocols.pc ] && is_source=1 ;;
    hyprland-protocols)
      dpkg -l 'hyprland-protocols' 2>/dev/null | grep -q '^ii' && is_apt=1
      [ -f /usr/local/share/pkgconfig/hyprland-protocols.pc ] && is_source=1 ;;
    hyprland-qt-support)
      dpkg -l 'hyprland-qt-support' 2>/dev/null | grep -q '^ii' && is_apt=1 ;;
    hyprland-qtutils)
      dpkg -l 'hyprland-qtutils' 2>/dev/null | grep -q '^ii' && is_apt=1
      { [ -f /usr/local/bin/hyprland-qt-utils ] || \
        [ -f /usr/local/bin/hyprland-qtutils ]; } && is_source=1 ;;
    hyprland)
      dpkg -l 'hyprland' 2>/dev/null | grep -q '^ii' && is_apt=1
      { [ -f /usr/local/bin/hyprland ] || [ -f /usr/local/bin/Hyprland ]; } && is_source=1 ;;
    hyprshutdown)
      dpkg -l 'hyprshutdown' 2>/dev/null | grep -q '^ii' && is_apt=1
      [ -f /usr/local/bin/hyprshutdown ] && is_source=1 ;;
    *)
      dpkg -l "$mod" 2>/dev/null | grep -q '^ii' && is_apt=1 ;;
  esac
  if [[ $is_apt -eq 1 && $is_source -eq 1 ]]; then echo "both"
  elif [[ $is_apt -eq 1 ]]; then echo "apt"
  elif [[ $is_source -eq 1 ]]; then echo "source"
  else echo "none"
  fi
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --with-deps)
      WITH_DEPS=1
      shift
      ;;
    --only)
      ONLY_LIST=${2:-}
      shift 2
      ;;
    --skip)
      SKIP_LIST=${2:-}
      shift 2
      ;;
    --check)
      CHECK_ONLY=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# Build module list based on --only/--skip
MODULES=()
if [[ -n "$ONLY_LIST" ]]; then
  IFS=',' read -r -a MODULES <<< "$ONLY_LIST"
else
  MODULES=("${DEFAULT_MODULES[@]}")
fi

if [[ -n "$SKIP_LIST" ]]; then
  IFS=',' read -r -a _SKIPS <<< "$SKIP_LIST"
  FILTERED=()
  for m in "${MODULES[@]}"; do
    skip_it=0
    for s in "${_SKIPS[@]}"; do
      if [[ "$m" == "$s" ]]; then
        skip_it=1
        break
      fi
    done
    if [[ $skip_it -eq 0 ]]; then
      FILTERED+=("$m")
    fi
  done
  MODULES=("${FILTERED[@]}")
fi

# Pre-scan: detect install method for every module in the run list
declare -A METHODS
for _m in "${MODULES[@]}"; do
  METHODS[$_m]="$(detect_module_method "$_m")"
done

# --check mode: report install methods and exit without building
if [[ $CHECK_ONLY -eq 1 ]]; then
  printf "\nInstall method check (no build):\n"
  printf "%-28s %s\n" "MODULE" "METHOD"
  printf "%-28s %s\n" "------" "------"
  for _m in "${MODULES[@]}"; do
    printf "%-28s %s\n" "$_m" "${METHODS[$_m]}"
  done
  exit 0
fi

# Pre-flight: warn about modules that are already apt-installed.
# A real (non-dry-run) source build would require purging them first.
_apt_conflicts=()
for _m in "${MODULES[@]}"; do
  case "${METHODS[$_m]}" in apt|both) _apt_conflicts+=("$_m") ;; esac
done
if [[ ${#_apt_conflicts[@]} -gt 0 ]]; then
  printf "\n[WARN] The following modules are already installed via apt.\n"
  printf "       A real source build would need them purged first:\n"
  for _m in "${_apt_conflicts[@]}"; do
    printf "  - %-28s [method: %s]\n" "$_m" "${METHODS[$_m]}"
  done
  printf "\n"
fi

# Optionally install dependencies (not a dry-run)
if [[ $WITH_DEPS -eq 1 ]]; then
  echo "[INFO] Installing dependencies via 00-dependencies.sh" | tee -a "$SUMMARY_LOG"
  if ! "$REPO_ROOT/install-scripts/00-dependencies.sh"; then
    echo "[ERROR] Dependencies installation failed. See logs under Install-Logs/." | tee -a "$SUMMARY_LOG"
    exit 1
  fi
fi

# Run each module with DRY_RUN=1 and capture exit codes
declare -A RESULTS

echo "[INFO] Starting dry-run build at $TS" | tee -a "$SUMMARY_LOG"

for mod in "${MODULES[@]}"; do
  script_path="$REPO_ROOT/install-scripts/$mod.sh"
  echo "\n=== $mod (DRY RUN) ===" | tee -a "$SUMMARY_LOG"
  if [[ ! -x "$script_path" ]]; then
    # Try to make executable if it exists
    if [[ -f "$script_path" ]]; then
      chmod +x "$script_path" || true
    fi
  fi
  if [[ ! -f "$script_path" ]]; then
    echo "[WARN] Missing script: $script_path" | tee -a "$SUMMARY_LOG"
    RESULTS[$mod]="MISSING"
    continue
  fi
  if DRY_RUN=1 "$script_path"; then
    RESULTS[$mod]="PASS"
  else
    RESULTS[$mod]="FAIL"
  fi
done

# Summary
{
  printf "\nSummary (dry-run):\n"
  printf "%-28s %-10s %s\n" "MODULE" "RESULT" "INSTALL-METHOD"
  for mod in "${MODULES[@]}"; do
    printf "%-28s %-10s %s\n" "$mod" "${RESULTS[$mod]:-SKIPPED}" "${METHODS[$mod]:-unknown}"
  done
  # Show current tag values to make changes visible during dry-runs
  if [[ -f "$REPO_ROOT/hypr-tags.env" ]]; then
    printf "\nCurrent versions (from %s):\n" "$REPO_ROOT/hypr-tags.env"
    grep -E '^[A-Z0-9_]+=' "$REPO_ROOT/hypr-tags.env" | sort
  fi
  printf "\nLogs: individual module logs are under Install-Logs/. This summary: %s\n" "$SUMMARY_LOG"
} | tee -a "$SUMMARY_LOG"

# Exit non-zero if any FAIL occurred
failed=0
for mod in "${MODULES[@]}"; do
  if [[ "${RESULTS[$mod]:-}" == "FAIL" ]]; then
    failed=1
  fi
done
exit $failed