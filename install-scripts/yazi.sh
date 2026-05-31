#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Yazi file manager install #

YAZI_GITHUB_RELEASE_API="https://api.github.com/repos/dariogriffo/yazi-debian/releases/latest"
YAZI_KEY_URL="https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc"
YAZI_KEY_PATH="/etc/apt/trusted.gpg.d/debian.griffo.io.gpg"
YAZI_REPO_FILE="/etc/apt/sources.list.d/yazi.list"
YAZI_POLICY_FILE="/etc/apt/preferences.d/yazi-prefer-github-release.pref"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change the working directory to the parent directory of the script
PARENT_DIR="$SCRIPT_DIR/.."
cd "$PARENT_DIR" || {
    echo "${ERROR} Failed to change directory to $PARENT_DIR"
    exit 1
}

# Source the global functions script
if ! source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"; then
    echo "Failed to source Global_functions.sh"
    exit 1
fi

# Set the name of the log file to include the current date and time
LOG="Install-Logs/install-$(date +%d-%H%M%S)_yazi.log"
DISTRO_ID=""
DISTRO_CODENAME=""
SYSTEM_ARCH=""
YAZI_RELEASE_TAG=""
YAZI_ASSET_NAME=""
YAZI_ASSET_URL=""
cleanup_local_yazi_binaries() {
    local local_bins=("/usr/local/bin/ya" "/usr/local/bin/yazi")
    local bin_path=""

    for bin_path in "${local_bins[@]}"; do
        if [ -e "$bin_path" ]; then
            if [ "${DRY_RUN:-0}" = "1" ]; then
                echo "[DRY-RUN] sudo rm -f $bin_path" | tee -a "$LOG"
            else
                echo "${INFO} Removing conflicting local binary ${YELLOW}${bin_path}${RESET}..." | tee -a "$LOG"
                if ! sudo rm -f "$bin_path" 2>&1 | tee -a "$LOG"; then
                    echo "${WARN} Failed to remove ${bin_path}; it may shadow packaged yazi binaries." | tee -a "$LOG"
                fi
            fi
        fi
    done
}

detect_system_info() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
    fi

    DISTRO_ID="${ID:-}"
    DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [ -z "$DISTRO_CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
        DISTRO_CODENAME="$(lsb_release -sc 2>/dev/null || true)"
    fi
    SYSTEM_ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
}

is_fallback_repo_enabled() {
    grep -R "^[[:space:]]*deb .*debian\\.griffo\\.io/apt" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | grep -q .
}

select_release_asset() {
    local release_json="$1"
    local pattern=""

    if [ "$DISTRO_ID" = "ubuntu" ]; then
        pattern="\\+${DISTRO_CODENAME}_${SYSTEM_ARCH}_ubu\\.deb$"
    elif [ "$DISTRO_ID" = "debian" ]; then
        pattern="\\+${DISTRO_CODENAME}_${SYSTEM_ARCH}\\.deb$"
    else
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        YAZI_RELEASE_TAG="$(printf '%s' "$release_json" | jq -r '.tag_name // empty')"
        YAZI_ASSET_URL="$(printf '%s' "$release_json" | jq -r --arg pattern "$pattern" '[.assets[] | select(.name | test($pattern)) | .browser_download_url] | first // empty')"
        YAZI_ASSET_NAME="$(printf '%s' "$release_json" | jq -r --arg pattern "$pattern" '[.assets[] | select(.name | test($pattern)) | .name] | first // empty')"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        local parsed=""
        parsed="$(python3 -c '
import json
import sys

distro = sys.argv[1]
codename = sys.argv[2]
arch = sys.argv[3]
data = json.load(sys.stdin)
tag = data.get("tag_name", "")

if distro == "ubuntu":
    suffix = f"+{codename}_{arch}_ubu.deb"
elif distro == "debian":
    suffix = f"+{codename}_{arch}.deb"
else:
    suffix = ""

name = ""
url = ""
for asset in data.get("assets", []):
    asset_name = asset.get("name", "")
    if suffix and asset_name.endswith(suffix):
        name = asset_name
        url = asset.get("browser_download_url", "")
        break

print(f"{tag}\t{name}\t{url}")
' "$DISTRO_ID" "$DISTRO_CODENAME" "$SYSTEM_ARCH" <<<"$release_json")" || return 1
        IFS=$'\t' read -r YAZI_RELEASE_TAG YAZI_ASSET_NAME YAZI_ASSET_URL <<<"$parsed"
        return 0
    fi

    return 1
}

set_preferred_yazi_policy() {
    local pinned_version="$1"
    [ -n "$pinned_version" ] || return 0

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY-RUN] Configure $YAZI_POLICY_FILE to pin yazi version $pinned_version at priority 1001" | tee -a "$LOG"
        return 0
    fi

    sudo tee "$YAZI_POLICY_FILE" >/dev/null <<EOF
Package: yazi
Pin: version $pinned_version
Pin-Priority: 1001
EOF
    echo "${OK} Added apt policy pin for Yazi version ${YELLOW}${pinned_version}${RESET} in ${YAZI_POLICY_FILE}." | tee -a "$LOG"
}

install_yazi_from_github_release() {
    local release_json=""
    local tmp_dir=""
    local deb_path=""
    local deb_version=""

    case "$DISTRO_ID" in
        ubuntu|debian) ;;
        *)
            echo "${WARN} Unsupported distro ID '${DISTRO_ID:-unknown}' for yazi-debian release matching." | tee -a "$LOG"
            return 1
            ;;
    esac

    if [ -z "$DISTRO_CODENAME" ] || [ -z "$SYSTEM_ARCH" ]; then
        echo "${WARN} Missing distro codename or architecture; cannot match yazi-debian release asset." | tee -a "$LOG"
        return 1
    fi

    release_json="$(curl -fsSL "$YAZI_GITHUB_RELEASE_API" 2>>"$LOG")" || {
        echo "${WARN} Failed to query latest yazi-debian GitHub release." | tee -a "$LOG"
        return 1
    }

    if ! select_release_asset "$release_json"; then
        echo "${WARN} Failed to parse GitHub release asset metadata." | tee -a "$LOG"
        return 1
    fi

    if [ -z "$YAZI_ASSET_URL" ] || [ -z "$YAZI_ASSET_NAME" ]; then
        echo "${WARN} No matching yazi-debian asset for ${DISTRO_ID}:${DISTRO_CODENAME} (${SYSTEM_ARCH})." | tee -a "$LOG"
        return 1
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY-RUN] curl -fL \"$YAZI_ASSET_URL\" -o /tmp/$YAZI_ASSET_NAME" | tee -a "$LOG"
        echo "[DRY-RUN] sudo apt-get install -y /tmp/$YAZI_ASSET_NAME" | tee -a "$LOG"
        return 0
    fi

    echo "${INFO} Installing ${YELLOW}Yazi${RESET} from yazi-debian release ${YELLOW}${YAZI_RELEASE_TAG}${RESET} (${YAZI_ASSET_NAME})..." | tee -a "$LOG"

    tmp_dir="$(mktemp -d)" || return 1
    deb_path="$tmp_dir/$YAZI_ASSET_NAME"

    if ! curl -fL "$YAZI_ASSET_URL" -o "$deb_path" 2>&1 | tee -a "$LOG"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! sudo apt-get install -y "$deb_path" 2>&1 | tee -a "$LOG"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    deb_version="$(dpkg-deb -f "$deb_path" Version 2>/dev/null || true)"
    rm -rf "$tmp_dir"

    if is_fallback_repo_enabled; then
        set_preferred_yazi_policy "$deb_version"
    fi

    return 0
}

configure_yazi_repo_fallback() {
    local yazi_repo_line="deb [signed-by=$YAZI_KEY_PATH] https://debian.griffo.io/apt $DISTRO_CODENAME main"
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY-RUN] curl -sS $YAZI_KEY_URL | sudo gpg --dearmor --yes -o $YAZI_KEY_PATH" | tee -a "$LOG"
        echo "[DRY-RUN] echo \"$yazi_repo_line\" | sudo tee $YAZI_REPO_FILE" | tee -a "$LOG"
        echo "[DRY-RUN] sudo apt update" | tee -a "$LOG"
        return 0
    fi

    echo "${INFO} Configuring ${YELLOW}Yazi${RESET} fallback APT repository for ${DISTRO_CODENAME}..." | tee -a "$LOG"
    curl -sS "$YAZI_KEY_URL" | sudo gpg --dearmor --yes -o "$YAZI_KEY_PATH" 2>&1 | tee -a "$LOG"

    if [ -f "$YAZI_REPO_FILE" ] && grep -Fxq "$yazi_repo_line" "$YAZI_REPO_FILE"; then
        echo "${INFO} Yazi apt source already configured." | tee -a "$LOG"
    else
        printf '%s\n' "$yazi_repo_line" | sudo tee "$YAZI_REPO_FILE" >/dev/null
        echo "${OK} Added Yazi apt source to ${YAZI_REPO_FILE}." | tee -a "$LOG"
    fi

    sudo apt update 2>&1 | tee -a "$LOG"
}

install_yazi_from_fallback_repo() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY-RUN] sudo apt-get -s install -y yazi" | tee -a "$LOG"
        sudo apt-get -s install -y yazi >/dev/null || true
        return 0
    fi
    install_package "yazi" "$LOG"
}

printf "\n%s - Installing ${SKY_BLUE}Yazi file manager${RESET}...\n" "${NOTE}"
detect_system_info
cleanup_local_yazi_binaries

if ! install_yazi_from_github_release; then
    echo "${WARN} Falling back to debian.griffo.io apt repository for Yazi." | tee -a "$LOG"
    configure_yazi_repo_fallback
    install_yazi_from_fallback_repo
fi

printf "\n%.0s" {1..1}
