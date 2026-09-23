#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# Quickshell (QtQuick-based shell toolkit) - Debian package installer
#
# Installs the distro-packaged Quickshell instead of building an older
# release from source into /usr/local (which shadowed the packaged binary
# and, on older releases, lacked Hyprland.usingLua -> broken Lua dispatchers).
#
# Repository selection:
#   - Debian trixie : trixie-backports
#   - forky+/sid/testing : standard repositories

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

mkdir -p "$PARENT_DIR/Install-Logs"
LOG="$PARENT_DIR/Install-Logs/install-$(date +%d-%H%M%S)_quickshell.log"

# Refresh sudo credentials once (install_package uses sudo internally)
if command -v sudo >/dev/null 2>&1; then
    sudo -v 2>/dev/null || sudo -v
fi

note() { echo -e "${NOTE} $*" | tee -a "$LOG"; }
info() { echo -e "${INFO} $*" | tee -a "$LOG"; }

# ------------------------------------------------------------------
# Resolve the Debian suite (prefer DEBIAN_SUITE from install.sh)
# ------------------------------------------------------------------
resolve_suite() {
    if [ -n "${DEBIAN_SUITE:-}" ]; then
        echo "$DEBIAN_SUITE"
        return
    fi
    local c=""
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release || true
        c="${VERSION_CODENAME:-}"
    fi
    if [ -z "$c" ] && command -v lsb_release >/dev/null 2>&1; then
        c="$(lsb_release -sc 2>/dev/null || true)"
    fi
    echo "$c"
}
SUITE="$(resolve_suite)"

# ------------------------------------------------------------------
# Remove legacy source-built Quickshell that shadows the packaged qs
# (previous installer versions built ~0.2.1 into /usr/local/bin).
# ------------------------------------------------------------------
cleanup_legacy_quickshell() {
    local f
    for f in /usr/local/bin/quickshell /usr/local/bin/qs; do
        if [ -e "$f" ] || [ -L "$f" ]; then
            note "Removing legacy source-built Quickshell artifact: $f"
            sudo rm -f "$f" 2>/dev/null || true
        fi
    done
    # The qs-system wrapper and QML override shim were only needed to work
    # around the old source build; the packaged Quickshell does not use them.
    if [ -e /usr/local/bin/qs-system ]; then
        note "Removing legacy Quickshell wrapper: /usr/local/bin/qs-system"
        sudo rm -f /usr/local/bin/qs-system 2>/dev/null || true
    fi
    if [ -d /usr/local/share/quickshell-overrides ]; then
        note "Removing legacy Quickshell override shim: /usr/local/share/quickshell-overrides"
        sudo rm -rf /usr/local/share/quickshell-overrides 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------
# Ensure trixie-backports is configured (standalone-safe; install.sh
# normally does this already when on trixie).
# ------------------------------------------------------------------
ensure_trixie_backports() {
    [ "$SUITE" = "trixie" ] || return 0
    if apt-cache policy quickshell 2>/dev/null | grep -q "trixie-backports"; then
        return 0
    fi
    # Already configured elsewhere?
    if sudo grep -RhsE '^[[:space:]]*deb[[:space:]]+\S+[[:space:]]+trixie-backports([[:space:]]|$)' \
        /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null | grep -q .; then
        return 0
    fi
    if sudo grep -RhsE '^[[:space:]]*Suites:[[:space:]].*\btrixie-backports\b' \
        /etc/apt/sources.list.d/*.sources 2>/dev/null | grep -q .; then
        return 0
    fi
    info "Enabling Debian trixie-backports repository for Quickshell..."
    sudo bash -c "cat > /etc/apt/sources.list.d/99-debian-trixie-backports.list <<EOF
# Added by Debian-Hyprland installer for Quickshell on trixie
deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware
EOF"
    sudo apt update 2>&1 | tee -a "$LOG"
}

pkg_candidate() {
    apt-cache policy quickshell 2>/dev/null | awk '/Candidate:/ {print $2}'
}

pkg_available_in_target() {
    local target="$1"
    apt-cache policy quickshell 2>/dev/null | grep -Eq "[[:space:]]${target}/"
}

# ------------------------------------------------------------------
# Install the Quickshell Debian package from the right repository
# ------------------------------------------------------------------
install_quickshell_pkg() {
    local cand
    case "$SUITE" in
    trixie)
        ensure_trixie_backports
        if pkg_available_in_target "trixie-backports"; then
            info "Installing Quickshell from trixie-backports..."
            install_package_target quickshell "trixie-backports"
        else
            cand="$(pkg_candidate)"
            if [ -n "$cand" ] && [ "$cand" != "(none)" ]; then
                note "quickshell not found in trixie-backports; installing from default suite ($cand)."
                install_package quickshell
            else
                echo "${ERROR} quickshell is not available in trixie-backports. Ensure the repository is enabled and run 'sudo apt update'." | tee -a "$LOG"
                return 1
            fi
        fi
        ;;
    *)
        cand="$(pkg_candidate)"
        if [ -n "$cand" ] && [ "$cand" != "(none)" ]; then
            info "Installing Quickshell from standard repositories${SUITE:+ (suite: $SUITE)}..."
            install_package quickshell
        else
            echo "${ERROR} quickshell package not available in the standard repositories${SUITE:+ for suite '$SUITE'}." | tee -a "$LOG"
            return 1
        fi
        ;;
    esac
}

# ------------------------------------------------------------------
# Best-effort: ensure Qt Quick runtime QML modules used by the shell
# configs are present (skips anything unavailable on this suite).
# ------------------------------------------------------------------
ensure_qml_runtime_modules() {
    local pkgs=(
        qml6-module-qtquick-effects
        qml6-module-qtquick-shapes
        qml6-module-qtquick-controls
        qml6-module-qtquick-layouts
        qml6-module-qt5compat-graphicaleffects
    )
    local p cand
    for p in "${pkgs[@]}"; do
        if dpkg -s "$p" >/dev/null 2>&1; then
            continue
        fi
        cand="$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ {print $2}')"
        if [ -n "$cand" ] && [ "$cand" != "(none)" ]; then
            install_package "$p"
        else
            note "Skipping $p (no candidate in APT)"
        fi
    done
}

printf "\n%s - Installing ${SKY_BLUE}Quickshell${RESET} from Debian repositories....\n" "${NOTE}"

cleanup_legacy_quickshell

if install_quickshell_pkg; then
    ensure_qml_runtime_modules

    if command -v qs >/dev/null 2>&1; then
        QS_BIN="$(command -v qs)"
        QS_VER="$(qs --version 2>/dev/null | head -n1 || true)"
        echo "${OK} Quickshell installed: ${MAGENTA}${QS_VER:-unknown}${RESET} (${QS_BIN})" | tee -a "$LOG"
        case "$QS_BIN" in
        /usr/local/*)
            echo "${WARN} 'qs' resolves to ${QS_BIN}; a /usr/local build may still shadow the packaged binary." | tee -a "$LOG"
            ;;
        esac
    else
        echo "${WARN} Quickshell package installed but 'qs' was not found on PATH." | tee -a "$LOG"
    fi
else
    echo "${ERROR} Failed to install Quickshell from Debian repositories." | tee -a "$LOG"
    exit 1
fi

printf "\n%.0s" {1..1}
