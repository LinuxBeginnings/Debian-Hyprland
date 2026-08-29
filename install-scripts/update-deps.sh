#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Update dependencies and summarize results

usage() {
  cat <<'EOF'
Usage: install-scripts/update-deps.sh [options]

Options:
  -d, --dry-run           Print scripts that would run, then exit.
  -p, --pre-cleanup       Run 0*-pre-cleanup.sh if present.
  -h, --help              Show this help and exit.

Env overrides:
  DEPENDENCIES_SCRIPT     Path to dependencies script
  PACKAGES_SCRIPT         Path to packages script
  WAYBAR_SCRIPT           Path to waybar script
  SWWW_SCRIPT             Path to swww/awww script
  NWG_DOCK_SCRIPT         Path to nwg-dock-hyprland script
  CHECK_SCRIPT            Path to final check script
EOF
}

DRY_RUN=0
INCLUDE_PRE_CLEANUP=0

while [ $# -gt 0 ]; do
  case "$1" in
  -d|--dry-run)
    DRY_RUN=1
    shift
    ;;
  -p|--pre-cleanup)
    INCLUDE_PRE_CLEANUP=1
    shift
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
LOG_DIR="$PARENT_DIR/Install-Logs"

mkdir -p "$LOG_DIR"
cd "$PARENT_DIR" || {
  echo "Failed to change directory to $PARENT_DIR"
  exit 1
}

mapfile -t scripts < <(ls "$SCRIPT_DIR"/0*-*.sh 2>/dev/null | sort)

pick_script() {
  local pattern="$1"
  local s
  for s in "${scripts[@]}"; do
    case "$s" in
      *"$pattern"*) echo "$s"; return 0 ;;
    esac
  done
  return 1
}

DEPENDENCIES_SCRIPT="${DEPENDENCIES_SCRIPT:-$(pick_script "dependencies" || pick_script "base")}"
PACKAGES_SCRIPT="${PACKAGES_SCRIPT:-$(pick_script "hypr-pkgs" || pick_script "pkgs")}"
CHECK_SCRIPT="${CHECK_SCRIPT:-$(pick_script "Final-Check" || pick_script "Final")}"
PRE_CLEANUP_SCRIPT="$(pick_script "pre-cleanup" || true)"
WAYBAR_SCRIPT="${WAYBAR_SCRIPT:-"$SCRIPT_DIR/waybar.sh"}"
SWWW_SCRIPT="${SWWW_SCRIPT:-"$SCRIPT_DIR/swww.sh"}"
NWG_DOCK_SCRIPT="${NWG_DOCK_SCRIPT:-"$SCRIPT_DIR/nwg-dock-hyprland.sh"}"

if [ -n "$DEPENDENCIES_SCRIPT" ] && [ ! -f "$DEPENDENCIES_SCRIPT" ]; then
  echo "Script not found: $DEPENDENCIES_SCRIPT"
  exit 1
fi
if [ -n "$PACKAGES_SCRIPT" ] && [ ! -f "$PACKAGES_SCRIPT" ]; then
  echo "Script not found: $PACKAGES_SCRIPT"
  exit 1
fi
if [ -n "$CHECK_SCRIPT" ] && [ ! -f "$CHECK_SCRIPT" ]; then
  echo "Script not found: $CHECK_SCRIPT"
  exit 1
fi
if [ "$INCLUDE_PRE_CLEANUP" -eq 1 ] && [ -n "$PRE_CLEANUP_SCRIPT" ] && [ ! -f "$PRE_CLEANUP_SCRIPT" ]; then
  echo "Script not found: $PRE_CLEANUP_SCRIPT"
  exit 1
fi
if [ -n "$WAYBAR_SCRIPT" ] && [ ! -f "$WAYBAR_SCRIPT" ]; then
  echo "Script not found: $WAYBAR_SCRIPT"
  exit 1
fi
if [ -n "$SWWW_SCRIPT" ] && [ ! -f "$SWWW_SCRIPT" ]; then
  echo "Script not found: $SWWW_SCRIPT"
  exit 1
fi
if [ -n "$NWG_DOCK_SCRIPT" ] && [ ! -f "$NWG_DOCK_SCRIPT" ]; then
  echo "Script not found: $NWG_DOCK_SCRIPT"
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run. Scripts that would execute:"
  [ -n "$DEPENDENCIES_SCRIPT" ] && echo "  dependencies: $DEPENDENCIES_SCRIPT"
  [ -n "$PACKAGES_SCRIPT" ] && echo "  packages: $PACKAGES_SCRIPT"
  [ "$INCLUDE_PRE_CLEANUP" -eq 1 ] && [ -n "$PRE_CLEANUP_SCRIPT" ] && echo "  pre-cleanup: $PRE_CLEANUP_SCRIPT"
  [ -n "$WAYBAR_SCRIPT" ] && echo "  waybar (source build): $WAYBAR_SCRIPT"
  if ! command -v awww >/dev/null 2>&1; then
    [ -n "$SWWW_SCRIPT" ] && echo "  swww/awww: $SWWW_SCRIPT (awww not installed)"
  else
    echo "  swww/awww: skipped (awww already installed at $(command -v awww))"
  fi
  if ! command -v nwg-dock-hyprland >/dev/null 2>&1; then
    [ -n "$NWG_DOCK_SCRIPT" ] && echo "  nwg-dock-hyprland: $NWG_DOCK_SCRIPT (nwg-dock-hyprland not installed)"
  else
    echo "  nwg-dock-hyprland: skipped (nwg-dock-hyprland already installed at $(command -v nwg-dock-hyprland))"
  fi
  [ -n "$CHECK_SCRIPT" ] && echo "  final check: $CHECK_SCRIPT"
  exit 0
fi

RUN_STAMP="$(date +%d-%H%M%S)"
DEPENDENCIES_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_dependencies.log"
PACKAGES_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_packages.log"
PRE_CLEANUP_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_pre-cleanup.log"
WAYBAR_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_waybar.log"
SWWW_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_swww.log"
NWG_DOCK_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_nwg_dock.log"
CHECK_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_check.log"

strip_ansi() {
  sed -r 's/\x1B\[[0-9;]*[mK]//g'
}

dependencies_status=0
packages_status=0
pre_cleanup_status=0
waybar_status=0
swww_status=0
nwg_dock_status=0
check_status=0

if [ -n "$DEPENDENCIES_SCRIPT" ]; then
  echo "Running dependencies script: $(basename "$DEPENDENCIES_SCRIPT")"
  bash "$DEPENDENCIES_SCRIPT" 2>&1 | tee "$DEPENDENCIES_LOG"
  dependencies_status=${PIPESTATUS[0]}
fi

if [ -n "$PACKAGES_SCRIPT" ]; then
  echo
  echo "Running packages script: $(basename "$PACKAGES_SCRIPT")"
  bash "$PACKAGES_SCRIPT" 2>&1 | tee "$PACKAGES_LOG"
  packages_status=${PIPESTATUS[0]}
fi

if [ "$INCLUDE_PRE_CLEANUP" -eq 1 ] && [ -n "$PRE_CLEANUP_SCRIPT" ]; then
  echo
  echo "Running pre-cleanup script: $(basename "$PRE_CLEANUP_SCRIPT")"
  bash "$PRE_CLEANUP_SCRIPT" 2>&1 | tee "$PRE_CLEANUP_LOG"
  pre_cleanup_status=${PIPESTATUS[0]}
fi

if [ -n "$WAYBAR_SCRIPT" ]; then
  echo
  echo "Running waybar source build: $(basename "$WAYBAR_SCRIPT")"
  bash "$WAYBAR_SCRIPT" 2>&1 | tee "$WAYBAR_LOG"
  waybar_status=${PIPESTATUS[0]}
fi

if ! command -v awww >/dev/null 2>&1; then
  if [ -n "$SWWW_SCRIPT" ]; then
    echo
    echo "awww not found. Running swww/awww script: $(basename "$SWWW_SCRIPT")"
    bash "$SWWW_SCRIPT" 2>&1 | tee "$SWWW_LOG"
    swww_status=${PIPESTATUS[0]}
  fi
else
  echo
  echo "awww already installed ($(command -v awww)). Skipping swww/awww script."
fi

if ! command -v nwg-dock-hyprland >/dev/null 2>&1; then
  if [ -n "$NWG_DOCK_SCRIPT" ]; then
    echo
    echo "nwg-dock-hyprland not found. Running nwg-dock-hyprland script: $(basename "$NWG_DOCK_SCRIPT")"
    bash "$NWG_DOCK_SCRIPT" 2>&1 | tee "$NWG_DOCK_LOG"
    nwg_dock_status=${PIPESTATUS[0]}
  fi
else
  echo
  echo "nwg-dock-hyprland already installed ($(command -v nwg-dock-hyprland)). Skipping nwg-dock-hyprland script."
fi

if [ -n "$CHECK_SCRIPT" ]; then
  echo
  echo "Running final check: $(basename "$CHECK_SCRIPT")"
  bash "$CHECK_SCRIPT" 2>&1 | tee "$CHECK_LOG"
  check_status=${PIPESTATUS[0]}
fi

clean_dependencies_log="$(mktemp)"
clean_packages_log="$(mktemp)"
clean_swww_log="$(mktemp)"
clean_nwg_dock_log="$(mktemp)"
clean_check_log="$(mktemp)"
if [ -f "$DEPENDENCIES_LOG" ]; then
  strip_ansi < "$DEPENDENCIES_LOG" > "$clean_dependencies_log"
fi
if [ -f "$PACKAGES_LOG" ]; then
  strip_ansi < "$PACKAGES_LOG" > "$clean_packages_log"
fi
if [ -f "$SWWW_LOG" ]; then
  strip_ansi < "$SWWW_LOG" > "$clean_swww_log"
fi
if [ -f "$NWG_DOCK_LOG" ]; then
  strip_ansi < "$NWG_DOCK_LOG" > "$clean_nwg_dock_log"
fi
if [ -f "$CHECK_LOG" ]; then
  strip_ansi < "$CHECK_LOG" > "$clean_check_log"
fi

mapfile -t installed_pkgs < <(cat "$clean_packages_log" "$clean_swww_log" "$clean_nwg_dock_log" 2>/dev/null | awk '/\[OK\] (Package |.*nwg-dock-hyprland)/{print $3}' | sort -u)
mapfile -t failed_pkgs < <(cat "$clean_packages_log" "$clean_swww_log" "$clean_nwg_dock_log" 2>/dev/null | awk '/failed to install|Installation failed for/{print $2}' | sort -u)

latest_final_log="$(ls -t "$LOG_DIR"/00_CHECK-*_installed.log 2>/dev/null | head -n 1)"
missing_pkgs=()
if [ -n "$latest_final_log" ] && [ -f "$latest_final_log" ]; then
  mapfile -t missing_pkgs < <(strip_ansi < "$latest_final_log" | awk 'NF==1')
fi

rm -f "$clean_dependencies_log" "$clean_packages_log" "$clean_swww_log" "$clean_nwg_dock_log" "$clean_check_log"

echo
echo "Summary"
echo "-------"
echo "Dependencies script: ${DEPENDENCIES_SCRIPT:-none}"
echo "Packages script: ${PACKAGES_SCRIPT:-none}"
if [ "$INCLUDE_PRE_CLEANUP" -eq 1 ]; then
  echo "Pre-cleanup script: ${PRE_CLEANUP_SCRIPT:-none}"
fi
echo "Waybar script: ${WAYBAR_SCRIPT:-none}"
if ! command -v awww >/dev/null 2>&1; then
  echo "SWWW/AWWW script: ${SWWW_SCRIPT:-none}"
else
  echo "SWWW/AWWW script: ${SWWW_SCRIPT:-none} (awww present)"
fi
if ! command -v nwg-dock-hyprland >/dev/null 2>&1; then
  echo "nwg-dock-hyprland script: ${NWG_DOCK_SCRIPT:-none}"
else
  echo "nwg-dock-hyprland script: ${NWG_DOCK_SCRIPT:-none} (nwg-dock-hyprland present)"
fi
echo "Final check script: ${CHECK_SCRIPT:-none}"
echo "Dependencies exit status: $dependencies_status"
echo "Packages exit status: $packages_status"
if [ "$INCLUDE_PRE_CLEANUP" -eq 1 ]; then
  echo "Pre-cleanup exit status: $pre_cleanup_status"
fi
echo "Waybar exit status: $waybar_status"
echo "SWWW/AWWW exit status: $swww_status"
echo "nwg-dock-hyprland exit status: $nwg_dock_status"
echo "Check exit status: $check_status"
echo

if [ ${#installed_pkgs[@]} -gt 0 ]; then
  echo "Installed packages (${#installed_pkgs[@]}): ${installed_pkgs[*]}"
else
  echo "Installed packages: none detected"
fi

if [ ${#failed_pkgs[@]} -gt 0 ]; then
  echo "Failed installs (${#failed_pkgs[@]}): ${failed_pkgs[*]}"
else
  echo "Failed installs: none detected"
fi

if [ ${#missing_pkgs[@]} -gt 0 ]; then
  echo "Missing packages from final check (${#missing_pkgs[@]}): ${missing_pkgs[*]}"
else
  echo "Missing packages from final check: none detected"
fi
