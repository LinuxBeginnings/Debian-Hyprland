#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Yazi file manager install #

YAZI_GITHUB_RELEASE_API="https://api.github.com/repos/sxyazi/yazi/releases/latest"

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

cleanup_legacy_yazi_repo() {
    local repo_files=(
        "/etc/apt/sources.list.d/yazi.list"
        "/etc/apt/preferences.d/yazi-prefer-github-release.pref"
        "/etc/apt/trusted.gpg.d/debian.griffo.io.gpg"
        "/etc/apt/keyrings/debian.griffo.io.gpg"
    )
    local f=""

    for f in "${repo_files[@]}"; do
        if [ -e "$f" ]; then
            if [ "${DRY_RUN:-0}" = "1" ]; then
                echo "[DRY-RUN] sudo rm -f $f" | tee -a "$LOG"
            else
                echo "${INFO} Removing legacy repository artifact ${YELLOW}${f}${RESET}..." | tee -a "$LOG"
                sudo rm -f "$f" 2>&1 | tee -a "$LOG" || true
            fi
        fi
    done

    if [ "${DRY_RUN:-0}" != "1" ]; then
        for list_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
            if [ -f "$list_file" ] && grep -Eq "debian\.griffo\.io|deb\.griffo\.io" "$list_file" 2>/dev/null; then
                echo "${INFO} Cleaning legacy griffo repository entry from ${YELLOW}${list_file}${RESET}..." | tee -a "$LOG"
                sudo sed -i '/griffo\.io/d' "$list_file" 2>&1 | tee -a "$LOG" || true
            fi
        done
    fi
}

cleanup_local_yazi_binaries() {
    local local_bins=("/usr/local/bin/ya" "/usr/local/bin/yazi")
    local bin_path=""

    for bin_path in "${local_bins[@]}"; do
        if [ -e "$bin_path" ]; then
            if [ "${DRY_RUN:-0}" = "1" ]; then
                echo "[DRY-RUN] sudo rm -f $bin_path" | tee -a "$LOG"
            else
                echo "${INFO} Removing local binary ${YELLOW}${bin_path}${RESET}..." | tee -a "$LOG"
                if ! sudo rm -f "$bin_path" 2>&1 | tee -a "$LOG"; then
                    echo "${WARN} Failed to remove ${bin_path}." | tee -a "$LOG"
                fi
            fi
        fi
    done
}

detect_arch_target() {
    local raw_arch=""
    raw_arch="$(dpkg --print-architecture 2>/dev/null || uname -m 2>/dev/null || echo "x86_64")"

    case "$raw_arch" in
        amd64|x86_64)
            printf "x86_64"
            ;;
        arm64|aarch64)
            printf "aarch64"
            ;;
        armhf|armv7l)
            printf "armv7"
            ;;
        riscv64)
            printf "riscv64gc"
            ;;
        i386|i686)
            printf "i686"
            ;;
        *)
            printf "%s" "$raw_arch"
            ;;
    esac
}

install_completions_from_dir() {
    local comp_dir="$1"
    [ -d "$comp_dir" ] || return 0

    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY-RUN] Install shell completions from $comp_dir" | tee -a "$LOG"
        return 0
    fi

    # Bash completion
    if [ -d /usr/share/bash-completion/completions ]; then
        [ -f "$comp_dir/yazi.bash" ] && sudo cp "$comp_dir/yazi.bash" /usr/share/bash-completion/completions/yazi 2>/dev/null || true
        [ -f "$comp_dir/ya.bash" ] && sudo cp "$comp_dir/ya.bash" /usr/share/bash-completion/completions/ya 2>/dev/null || true
    fi

    # Zsh completion
    local zsh_target="/usr/local/share/zsh/site-functions"
    if [ -d /usr/share/zsh/vendor-completions ]; then
        zsh_target="/usr/share/zsh/vendor-completions"
    fi
    sudo mkdir -p "$zsh_target" 2>/dev/null || true
    [ -f "$comp_dir/_yazi" ] && sudo cp "$comp_dir/_yazi" "$zsh_target/_yazi" 2>/dev/null || true
    [ -f "$comp_dir/_ya" ] && sudo cp "$comp_dir/_ya" "$zsh_target/_ya" 2>/dev/null || true

    # Fish completion
    if [ -d /usr/share/fish/vendor_completions.d ]; then
        [ -f "$comp_dir/yazi.fish" ] && sudo cp "$comp_dir/yazi.fish" /usr/share/fish/vendor_completions.d/yazi.fish 2>/dev/null || true
        [ -f "$comp_dir/ya.fish" ] && sudo cp "$comp_dir/ya.fish" /usr/share/fish/vendor_completions.d/ya.fish 2>/dev/null || true
    fi
}

install_yazi_from_github() {
    local arch_target=""
    local release_json=""
    local tag=""
    local deb_url=""
    local deb_name=""
    local zip_url=""
    local zip_name=""

    arch_target="$(detect_arch_target)"

    echo "${INFO} Fetching latest ${YELLOW}Yazi${RESET} release from official GitHub (${YAZI_GITHUB_RELEASE_API})..." | tee -a "$LOG"

    release_json="$(curl -fsSL "$YAZI_GITHUB_RELEASE_API" 2>>"$LOG")" || {
        echo "${ERROR} Failed to query official Yazi GitHub release API." | tee -a "$LOG"
        return 1
    }

    if command -v jq >/dev/null 2>&1; then
        tag="$(printf '%s' "$release_json" | jq -r '.tag_name // empty')"
        deb_url="$(printf '%s' "$release_json" | jq -r --arg gnu "yazi-${arch_target}-unknown-linux-gnu.deb" --arg musl "yazi-${arch_target}-unknown-linux-musl.deb" '[.assets[] | select(.name == $gnu or .name == $musl) | .browser_download_url] | first // empty')"
        deb_name="$(printf '%s' "$release_json" | jq -r --arg gnu "yazi-${arch_target}-unknown-linux-gnu.deb" --arg musl "yazi-${arch_target}-unknown-linux-musl.deb" '[.assets[] | select(.name == $gnu or .name == $musl) | .name] | first // empty')"
        zip_url="$(printf '%s' "$release_json" | jq -r --arg gnu "yazi-${arch_target}-unknown-linux-gnu.zip" --arg musl "yazi-${arch_target}-unknown-linux-musl.zip" '[.assets[] | select(.name == $gnu or .name == $musl) | .browser_download_url] | first // empty')"
        zip_name="$(printf '%s' "$release_json" | jq -r --arg gnu "yazi-${arch_target}-unknown-linux-gnu.zip" --arg musl "yazi-${arch_target}-unknown-linux-musl.zip" '[.assets[] | select(.name == $gnu or .name == $musl) | .name] | first // empty')"
    elif command -v python3 >/dev/null 2>&1; then
        local parsed=""
        parsed="$(python3 -c '
import json, sys
arch = sys.argv[1]
gnu_deb = f"yazi-{arch}-unknown-linux-gnu.deb"
musl_deb = f"yazi-{arch}-unknown-linux-musl.deb"
gnu_zip = f"yazi-{arch}-unknown-linux-gnu.zip"
musl_zip = f"yazi-{arch}-unknown-linux-musl.zip"

data = json.load(sys.stdin)
tag = data.get("tag_name", "")
deb_name, deb_url, zip_name, zip_url = "", "", "", ""

for asset in data.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name == gnu_deb:
        deb_name, deb_url = name, url
    elif not deb_url and name == musl_deb:
        deb_name, deb_url = name, url
    elif name == gnu_zip:
        zip_name, zip_url = name, url
    elif not zip_url and name == musl_zip:
        zip_name, zip_url = name, url

print(f"{tag}\t{deb_name}\t{deb_url}\t{zip_name}\t{zip_url}")
' "$arch_target" <<<"$release_json")" || return 1
        IFS=$'\t' read -r tag deb_name deb_url zip_name zip_url <<<"$parsed"
    fi

    if [ -z "$tag" ]; then
        echo "${ERROR} Could not parse release tag from Yazi GitHub API response." | tee -a "$LOG"
        return 1
    fi

    echo "${INFO} Found official Yazi release: ${YELLOW}${tag}${RESET} (architecture: ${arch_target})" | tee -a "$LOG"

    # Strategy 1: Install official .deb package if available
    if [ -n "$deb_url" ]; then
        echo "${INFO} Attempting installation via official deb package: ${YELLOW}${deb_name}${RESET}..." | tee -a "$LOG"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            echo "[DRY-RUN] curl -fL \"$deb_url\" -o /tmp/$deb_name" | tee -a "$LOG"
            echo "[DRY-RUN] sudo apt-get install -y /tmp/$deb_name" | tee -a "$LOG"
            cleanup_local_yazi_binaries
            return 0
        fi

        local tmp_dir=""
        tmp_dir="$(mktemp -d)" || return 1
        local deb_path="$tmp_dir/$deb_name"

        if curl -fsSL "$deb_url" -o "$deb_path" 2>&1 | tee -a "$LOG"; then
            cleanup_local_yazi_binaries
            if sudo apt-get install -y "$deb_path" 2>&1 | tee -a "$LOG" || { sudo dpkg -i "$deb_path" 2>&1 | tee -a "$LOG" && sudo apt-get install -f -y 2>&1 | tee -a "$LOG"; }; then
                rm -rf "$tmp_dir"
                echo "${OK} Successfully installed ${YELLOW}Yazi ${tag}${RESET} via deb package." | tee -a "$LOG"
                return 0
            else
                echo "${WARN} Failed to install deb package. Falling back to prebuilt binary zip..." | tee -a "$LOG"
            fi
        else
            echo "${WARN} Failed to download deb package. Falling back to prebuilt binary zip..." | tee -a "$LOG"
        fi
        rm -rf "$tmp_dir"
    fi

    # Strategy 2: Install from prebuilt binary zip
    if [ -n "$zip_url" ]; then
        echo "${INFO} Installing ${YELLOW}Yazi${RESET} from prebuilt binary archive: ${YELLOW}${zip_name}${RESET}..." | tee -a "$LOG"
        if [ "${DRY_RUN:-0}" = "1" ]; then
            echo "[DRY-RUN] curl -fL \"$zip_url\" -o /tmp/$zip_name" | tee -a "$LOG"
            echo "[DRY-RUN] Extract yazi and ya binaries to /usr/local/bin/" | tee -a "$LOG"
            return 0
        fi

        local tmp_dir=""
        tmp_dir="$(mktemp -d)" || return 1
        local zip_path="$tmp_dir/$zip_name"

        if ! curl -fsSL "$zip_url" -o "$zip_path" 2>&1 | tee -a "$LOG"; then
            echo "${ERROR} Failed to download Yazi binary archive from $zip_url" | tee -a "$LOG"
            rm -rf "$tmp_dir"
            return 1
        fi

        local extract_dir="$tmp_dir/extracted"
        mkdir -p "$extract_dir"

        if command -v unzip >/dev/null 2>&1; then
            unzip -q "$zip_path" -d "$extract_dir" 2>&1 | tee -a "$LOG"
        elif command -v 7z >/dev/null 2>&1; then
            7z x -y "$zip_path" -o"$extract_dir" >>"$LOG" 2>&1
        elif command -v python3 >/dev/null 2>&1; then
            python3 -m zipfile -e "$zip_path" "$extract_dir" 2>&1 | tee -a "$LOG"
        else
            echo "${ERROR} No extraction tool (unzip, 7z, python3) found to extract $zip_name" | tee -a "$LOG"
            rm -rf "$tmp_dir"
            return 1
        fi

        local yazi_bin=""
        local ya_bin=""
        yazi_bin="$(find "$extract_dir" -type f -name "yazi" -perm -111 -o -type f -name "yazi" | head -n 1)"
        ya_bin="$(find "$extract_dir" -type f -name "ya" -perm -111 -o -type f -name "ya" | head -n 1)"

        if [ -z "$yazi_bin" ] || [ ! -f "$yazi_bin" ]; then
            echo "${ERROR} Extracted archive does not contain 'yazi' binary." | tee -a "$LOG"
            rm -rf "$tmp_dir"
            return 1
        fi

        sudo install -m 0755 "$yazi_bin" /usr/local/bin/yazi 2>&1 | tee -a "$LOG"
        if [ -n "$ya_bin" ] && [ -f "$ya_bin" ]; then
            sudo install -m 0755 "$ya_bin" /usr/local/bin/ya 2>&1 | tee -a "$LOG"
        fi

        local comp_dir=""
        comp_dir="$(find "$extract_dir" -type d -name "completions" | head -n 1)"
        if [ -n "$comp_dir" ]; then
            install_completions_from_dir "$comp_dir"
        fi

        rm -rf "$tmp_dir"
        echo "${OK} Successfully installed ${YELLOW}Yazi ${tag}${RESET} to /usr/local/bin." | tee -a "$LOG"
        return 0
    fi

    echo "${ERROR} No compatible asset found in Yazi release ${tag} for ${arch_target}." | tee -a "$LOG"
    return 1
}

printf "\n%s - Installing ${SKY_BLUE}Yazi file manager${RESET}...\n" "${NOTE}"

cleanup_legacy_yazi_repo

if ! install_yazi_from_github; then
    echo "${ERROR} Failed to install Yazi from official GitHub releases." | tee -a "$LOG"
    exit 1
fi

if command -v yazi >/dev/null 2>&1; then
    installed_ver="$(yazi --version 2>/dev/null || echo "installed")"
    echo "${OK} ${YELLOW}Yazi${RESET} is ready: ${GREEN}${installed_ver}${RESET}" | tee -a "$LOG"
else
    echo "${WARN} Yazi was installed but is not found in PATH." | tee -a "$LOG"
fi

printf "\n%.0s" {1..1}
