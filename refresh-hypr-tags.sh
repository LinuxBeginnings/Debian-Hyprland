#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# Refresh hypr-tags.env with latest release tags from upstream
# Safe to run multiple times; creates timestamped backups

set -euo pipefail

GREEN=$'\e[32m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
BOLD=$'\e[1m'
RESET=$'\e[0m'

REPO_ROOT=$(pwd)
TAGS_FILE="$REPO_ROOT/hypr-tags.env"
LOG_DIR="$REPO_ROOT/Install-Logs"
mkdir -p "$LOG_DIR"
TS=$(date +%F-%H%M%S)
SUMMARY_LOG="$LOG_DIR/refresh-tags-$TS.log"

usage() {
  cat <<'EOF'
refresh-hypr-tags.sh
Refresh hypr-tags.env with latest GitHub release tags.

Usage:
  ./refresh-hypr-tags.sh
  FORCE=1 ./refresh-hypr-tags.sh
  ./refresh-hypr-tags.sh --force-update
  ./refresh-hypr-tags.sh --get-latest
  ./refresh-hypr-tags.sh --get-lastest

Notes:
  - By default, only updates keys set to auto/latest (or unset).
  - Use FORCE=1 or --force-update to override pinned values.
EOF
}

compare_versions() {
  local a="$1" b="$2"
  if [[ "$a" == "$b" ]]; then
    printf '0'
    return
  fi
  local first
  first=$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)
  if [[ "$first" == "$a" ]]; then
    printf '%s' '-1'
  else
    printf '%s' '1'
  fi
}

format_change_line() {
  local key="$1" old="$2" new="$3" color="$YELLOW"
  if [[ -n "$old" && ! "$old" =~ ^(auto|latest)$ ]]; then
    local cmp
    cmp=$(compare_versions "$new" "$old")
    if [[ "$cmp" == "-1" ]]; then
      color="$RED"
    else
      color="$GREEN"
    fi
  fi
  if [[ -t 1 ]]; then
    printf "%s%s%s: %s -> %s%s" "$BOLD" "$color" "$key" "${old:-<unset>}" "$new" "$RESET"
  else
    printf "%s: %s -> %s" "$key" "${old:-<unset>}" "$new"
  fi
}

format_tag_line() {
  local key="$1" val="$2" old="$3"
  local name_color="$GREEN" ver_color="$BLUE" emphasis=""
  local downgraded=0
  if [[ -n "$old" && ! "$old" =~ ^(auto|latest)$ ]]; then
    local cmp
    cmp=$(compare_versions "$val" "$old")
    if [[ "$cmp" == "-1" ]]; then
      downgraded=1
    else
      emphasis="$BOLD"
    fi
  fi
  if [[ -t 1 ]]; then
    if [[ $downgraded -eq 1 ]]; then
      printf "%s%s%s Version: %s%s%s" "$BOLD" "$RED" "$key" "$val" "$RESET" "$RESET"
    else
      printf "%s%s%s Version: %s%s%s%s" "$emphasis" "$name_color" "$key" "$RESET" "$emphasis" "$ver_color" "$val"
      printf "%s" "$RESET"
    fi
  else
    printf "%s Version: %s" "$key" "$val"
  fi
}

# Arg parsing (minimal/backwards compatible)
FORCE=${FORCE:-0}
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --force-update|--force)
      FORCE=1
      ;;
    # Alias for user ergonomics; refresh always checks latest tags.
    --get-latest|--get-lastest|--fetch-latest)
      :
      ;;
    *)
      echo "[WARN] Unknown argument ignored: $arg" | tee -a "$SUMMARY_LOG"
      ;;
  esac
done

# Ensure tags file exists
if [[ ! -f "$TAGS_FILE" ]]; then
cat > "$TAGS_FILE" <<'EOF'
# Default Hyprland stack versions
HYPRLAND_TAG=v0.53.3
AQUAMARINE_TAG=v0.10.0
HYPRUTILS_TAG=v0.11.0
HYPRLANG_TAG=v0.6.8
HYPRGRAPHICS_TAG=v0.5.0
HYPRTOOLKIT_TAG=v0.4.1
HYPRWAYLAND_SCANNER_TAG=v0.4.5
HYPRLAND_PROTOCOLS_TAG=v0.7.0
HYPRLAND_QT_SUPPORT_TAG=v0.1.0
HYPRLAND_QTUTILS_TAG=v0.1.5
HYPRLAND_GUIUTILS_TAG=v0.2.0
HYPRWIRE_TAG=v0.2.1
WAYLAND_PROTOCOLS_TAG=1.46
EOF
fi

# Backup
cp "$TAGS_FILE" "$TAGS_FILE.bak-$TS"
echo "[INFO] Backed up $TAGS_FILE to $TAGS_FILE.bak-$TS" | tee -a "$SUMMARY_LOG"

if ! command -v curl >/dev/null 2>&1; then
  echo "[ERROR] curl is required to refresh tags" | tee -a "$SUMMARY_LOG"
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "[ERROR] git is required to refresh tags" | tee -a "$SUMMARY_LOG"
  exit 1
fi

# Optional GitHub token to avoid rate limits (export GITHUB_TOKEN or GH_TOKEN).
GITHUB_TOKEN=${GITHUB_TOKEN:-${GH_TOKEN:-}}

fetch_url() {
  local url="$1"
  local accept_header="$2"
  local auth_header=()
  local response status body

  if [[ -n "${GITHUB_TOKEN:-}" && "$url" == https://api.github.com/* ]]; then
    auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  response=$(curl -sS \
    --retry 3 --retry-delay 1 \
    -H "User-Agent: Debian-Hyprland/refresh-hypr-tags" \
    ${accept_header:+-H "$accept_header"} \
    "${auth_header[@]}" \
    -w "\nHTTP_STATUS:%{http_code}" \
    "$url" || true)

  status=$(printf '%s' "$response" | awk -F: '/^HTTP_STATUS:/ {print $2}' | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')

  printf '%s\n' "$status"
  printf '%s' "$body"
}

# Map of env var -> repo
# (Some modules may not publish GitHub releases; in that case the tag may not refresh.)
declare -A repos=(
  [HYPRLAND_TAG]="hyprwm/Hyprland"
  [AQUAMARINE_TAG]="hyprwm/aquamarine"
  [HYPRUTILS_TAG]="hyprwm/hyprutils"
  [HYPRLANG_TAG]="hyprwm/hyprlang"
  [HYPRGRAPHICS_TAG]="hyprwm/hyprgraphics"
  [HYPRTOOLKIT_TAG]="hyprwm/hyprtoolkit"
  [HYPRWAYLAND_SCANNER_TAG]="hyprwm/hyprwayland-scanner"
  [HYPRLAND_PROTOCOLS_TAG]="hyprwm/hyprland-protocols"
  [HYPRLAND_QT_SUPPORT_TAG]="hyprwm/hyprland-qt-support"
  [HYPRLAND_QTUTILS_TAG]="hyprwm/hyprland-qtutils"
  [HYPRLAND_GUIUTILS_TAG]="hyprwm/hyprland-guiutils"
  [HYPRWIRE_TAG]="hyprwm/hyprwire"
  [HYPRWIRE_PROTOCOLS_TAG]="hyprwm/hyprwire-protocols"
  [WAYLAND_PROTOCOLS_TAG]="wayland-project/wayland-protocols"
  # Additional apps/utilities
  [HYPRIDLE_TAG]="hyprwm/hypridle"
  [HYPRLOCK_TAG]="hyprwm/hyprlock"
  [HYPRPICKER_TAG]="hyprwm/hyprpicker"
  [HYPRSHUTDOWN_TAG]="hyprwm/hyprshutdown"
  [HYPRPWCENTER_TAG]="hyprwm/hyprpwcenter"
  [HYPRTAVERN_TAG]="hyprwm/hyprtavern"
  [HYPRSUNSET_TAG]="hyprwm/hyprsunset"
  [HYPRLAUNCHER_TAG]="hyprwm/hyprlauncher"
  [HYPRSYSTEMINFO_TAG]="hyprwm/hyprsysteminfo"
)

# Read existing
declare -A cur
while IFS='=' read -r k v; do
  [[ -z "${k:-}" || "$k" =~ ^# ]] && continue
  cur[$k]="$v"
done < "$TAGS_FILE"

# Fetch latest, but only update keys set to 'auto' or 'latest' unless forced
changes=()
for key in "${!repos[@]}"; do
  repo="${repos[$key]}"
  tag=""
  echo "[INFO] Checking latest tag for $repo" | tee -a "$SUMMARY_LOG"

  if [[ "$repo" == "wayland-project/wayland-protocols" ]]; then
    # Official releases live on GitLab, not GitHub.
    url="https://gitlab.freedesktop.org/api/v4/projects/wayland%2Fwayland-protocols/repository/tags?per_page=1"
  else
    url="https://api.github.com/repos/$repo/releases/latest"
  fi
  # Be resilient to transient API errors; handle 403/404 explicitly.
  status_and_body=$(fetch_url "$url" "Accept: application/vnd.github+json")
  status=$(printf '%s' "$status_and_body" | head -n1)
  body=$(printf '%s' "$status_and_body" | tail -n +2)

  if [[ "$status" == "403" && "$repo" != "wayland-project/wayland-protocols" ]]; then
    # Fall back to git ls-remote to avoid API rate limits.
    tag=$(git ls-remote --tags --refs "https://github.com/$repo.git" \
      | awk -F/ '{print $NF}' | sort -V | tail -n1 || true)
    if [[ -z "$tag" ]]; then
      echo "[WARN] HTTP 403 from API for $repo (rate limit or auth required). Set GITHUB_TOKEN to avoid limits." | tee -a "$SUMMARY_LOG"
      continue
    fi
  fi

  if [[ "$status" == "404" && "$repo" != "wayland-project/wayland-protocols" ]]; then
    # Some repos don't publish GitHub releases; fall back to tags.
    tags_url="https://api.github.com/repos/$repo/tags?per_page=1"
    status_and_body=$(fetch_url "$tags_url" "Accept: application/vnd.github+json")
    status=$(printf '%s' "$status_and_body" | head -n1)
    body=$(printf '%s' "$status_and_body" | tail -n +2)
  fi

  if [[ -z "${tag:-}" && ( -z "$body" || "$status" == "404" ) ]]; then
    echo "[WARN] Empty response for $repo" | tee -a "$SUMMARY_LOG"
    continue
  fi
  if [[ -z "${tag:-}" ]]; then
    if command -v jq >/dev/null 2>&1; then
      tag=$(printf '%s' "$body" | jq -r 'if type=="object" then (.tag_name // empty) elif type=="array" then (.[0].name // empty) else empty end')
    else
      tag=$(printf '%s' "$body" | grep -m1 -E '"tag_name"|"name"' | sed -E 's/.*"(tag_name|name)"\s*:\s*"([^"]+)".*/\2/')
    fi
  fi
  if [[ -z "$tag" ]]; then
    # Final fallback: query git tags directly.
    if [[ "$repo" == "wayland-project/wayland-protocols" ]]; then
      tag=$(git ls-remote --tags --refs "https://gitlab.freedesktop.org/wayland/wayland-protocols.git" \
        | awk -F/ '{print $NF}' | sort -V | tail -n1 || true)
    else
      tag=$(git ls-remote --tags --refs "https://github.com/$repo.git" \
        | awk -F/ '{print $NF}' | sort -V | tail -n1 || true)
    fi
  fi
  if [[ -z "$tag" ]]; then
    echo "[WARN] Could not parse tag for $repo" | tee -a "$SUMMARY_LOG"
    continue
  fi
  existing="${cur[$key]:-}"
  if [[ $FORCE -eq 1 ]] || [[ "$existing" =~ ^(auto|latest)$ ]] || [[ -z "$existing" ]]; then
    cur[$key]="$tag"
    if [[ "$existing" != "$tag" ]]; then
      changes+=("$key|$existing|$tag")
    fi
    echo "[OK] $key := $tag" | tee -a "$SUMMARY_LOG"
  else
    echo "[SKIP] $key pinned ($existing), not overriding" | tee -a "$SUMMARY_LOG"
  fi
done

# Show change summary and prompt before writing (interactive only)
if [[ -t 0 && ${#changes[@]} -gt 0 ]]; then
  printf "\nPlanned tag updates (refresh-hypr-tags.sh):\n" | tee -a "$SUMMARY_LOG"
  printf "%s\n" "${changes[@]}" | sort | while IFS='|' read -r k o n; do
    format_change_line "$k" "$o" "$n"
    printf "\n"
  done | tee -a "$SUMMARY_LOG"
  printf "\nProceed with writing updated tags to %s? [Y/n]: " "$TAGS_FILE"
  read -r ans || true
  ans=${ans:-Y}
  case "$ans" in
    [nN]|[nN][oO])
      echo "[INFO] User aborted tag update; leaving $TAGS_FILE unchanged." | tee -a "$SUMMARY_LOG"
      exit 0
      ;;
  esac
fi

# Write back
{
  for k in "${!cur[@]}"; do
    echo "$k=${cur[$k]}"
  done | sort
} > "$TAGS_FILE"

echo "[OK] Refreshed tags written to $TAGS_FILE" | tee -a "$SUMMARY_LOG"

printf "\n%sUpdated versions%s (from %s):\n" "$BOLD" "$RESET" "$TAGS_FILE"
declare -A changed_old
if [[ ${#changes[@]} -gt 0 ]]; then
  for item in "${changes[@]}"; do
    IFS='|' read -r k o n <<<"$item"
    [[ -z "$k" ]] && continue
    changed_old["$k"]="$o"
  done
fi
while IFS='=' read -r key val; do
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  format_tag_line "$key" "$val" "${changed_old[$key]:-}"
  printf "\n"
done < <(grep -E '^[A-Z0-9_]+=' "$TAGS_FILE" | sort)

printf "\n%sChanges applied this run:%s\n" "$BOLD" "$RESET"
if [[ ${#changes[@]} -gt 0 ]]; then
  printf "%s\n" "${changes[@]}" | sort | while IFS='|' read -r k o n; do
    format_change_line "$k" "$o" "$n"
    printf "\n"
  done
else
  printf "(none)\n"
fi
