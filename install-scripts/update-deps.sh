#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Update dependencies and summarize results

## Repo-specific script names (override via env if needed)
DEPENDENCIES_SCRIPT_NAME="${DEPENDENCIES_SCRIPT_NAME:-00-dependencies.sh}"
PACKAGES_SCRIPT_NAME="${PACKAGES_SCRIPT_NAME:-01-hypr-pkgs.sh}"
CHECK_SCRIPT_NAME="${CHECK_SCRIPT_NAME:-03-Final-Check.sh}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$SCRIPT_DIR/.."
LOG_DIR="$PARENT_DIR/Install-Logs"

mkdir -p "$LOG_DIR"
cd "$PARENT_DIR" || {
  echo "Failed to change directory to $PARENT_DIR"
  exit 1
}

DEPENDENCIES_SCRIPT="$SCRIPT_DIR/$DEPENDENCIES_SCRIPT_NAME"
PACKAGES_SCRIPT="$SCRIPT_DIR/$PACKAGES_SCRIPT_NAME"
CHECK_SCRIPT="$SCRIPT_DIR/$CHECK_SCRIPT_NAME"

for script in "$DEPENDENCIES_SCRIPT" "$PACKAGES_SCRIPT" "$CHECK_SCRIPT"; do
  if [ ! -f "$script" ]; then
    echo "Script not found: $script"
    exit 1
  fi
done

RUN_STAMP="$(date +%d-%H%M%S)"
DEPENDENCIES_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_dependencies.log"
PACKAGES_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_packages.log"
CHECK_LOG="$LOG_DIR/update-deps-${RUN_STAMP}_check.log"

strip_ansi() {
  sed -r 's/\x1B\[[0-9;]*[mK]//g'
}

echo "Running dependencies script: $DEPENDENCIES_SCRIPT_NAME"
bash "$DEPENDENCIES_SCRIPT" 2>&1 | tee "$DEPENDENCIES_LOG"
dependencies_status=${PIPESTATUS[0]}

echo
echo "Running packages script: $PACKAGES_SCRIPT_NAME"
bash "$PACKAGES_SCRIPT" 2>&1 | tee "$PACKAGES_LOG"
packages_status=${PIPESTATUS[0]}

echo
echo "Running final check: $CHECK_SCRIPT_NAME"
bash "$CHECK_SCRIPT" 2>&1 | tee "$CHECK_LOG"
check_status=${PIPESTATUS[0]}

clean_dependencies_log="$(mktemp)"
clean_packages_log="$(mktemp)"
clean_check_log="$(mktemp)"
strip_ansi < "$DEPENDENCIES_LOG" > "$clean_dependencies_log"
strip_ansi < "$PACKAGES_LOG" > "$clean_packages_log"
strip_ansi < "$CHECK_LOG" > "$clean_check_log"

mapfile -t installed_pkgs < <(awk '/\[OK\] Package /{print $3}' "$clean_packages_log" | sort -u)
mapfile -t failed_pkgs < <(awk '/failed to install/{print $2}' "$clean_packages_log" | sort -u)

latest_final_log="$(ls -t "$LOG_DIR"/00_CHECK-*_installed.log 2>/dev/null | head -n 1)"
missing_pkgs=()
if [ -n "$latest_final_log" ] && [ -f "$latest_final_log" ]; then
  mapfile -t missing_pkgs < <(strip_ansi < "$latest_final_log" | awk 'NF==1')
fi

rm -f "$clean_dependencies_log" "$clean_packages_log" "$clean_check_log"

echo
echo "Summary"
echo "-------"
echo "Dependencies script: $DEPENDENCIES_SCRIPT_NAME"
echo "Packages script: $PACKAGES_SCRIPT_NAME"
echo "Final check script: $CHECK_SCRIPT_NAME"
echo "Dependencies exit status: $dependencies_status"
echo "Packages exit status: $packages_status"
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
