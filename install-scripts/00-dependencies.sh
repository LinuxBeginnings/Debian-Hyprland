#!/bin/bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# main dependencies #
# 22 Aug 2024 - NOTE will trim this more down

# packages neeeded
dependencies=(
    build-essential
    cmake
    cmake-extras
    clang
    llvm
    pkgconf
    curl
    findutils
    gawk
    gettext
    gir1.2-graphene-1.0
    git
    glslang-tools
    gobject-introspection
    golang
    hwdata
    jq
    libavcodec-dev
    libavformat-dev
    libavutil-dev
    libcairo2-dev
    libdeflate-dev
    libdisplay-info-dev
    libdrm-dev
    libegl-dev
    libegl1-mesa-dev
    libgbm-dev
    libgdk-pixbuf-2.0-dev
    libgdk-pixbuf2.0-bin
    libgirepository1.0-dev
    libgl1-mesa-dev
    libgraphene-1.0-0
    libgraphene-1.0-dev
    libgtk-3-dev
    libgulkan-0.15-0t64
    libgulkan-dev
    libinih-dev
    libiniparser-dev
    libinput-dev
    libjbig-dev
    libjpeg-dev
    libjpeg62-turbo-dev
    liblerc-dev
    libliftoff-dev
    liblzma-dev
    libnotify-bin
    libpam0g-dev
    libpango1.0-dev
    libpipewire-0.3-dev
    libqt6svg6
    libsdbus-c++-dev
    libseat-dev
    libstartup-notification0-dev
    libswresample-dev
    libsystemd-dev
    libtiff-dev
    libtiffxx6
    libtomlplusplus-dev
    libudev-dev
    libvkfft-dev
    libvulkan-dev
    libvulkan-volk-dev
    libwayland-dev
    libwayland-bin
    libwebp-dev
    libxcb-composite0-dev
    libxcb-cursor-dev
    libxcb-dri3-dev
    libxcb-ewmh-dev
    libxcb-icccm4-dev
    libxcb-present-dev
    libxcb-render-util0-dev
    libxcb-res0-dev
    libxcb-util-dev
    libxcb-xinerama0-dev
    libxcb-xinput-dev
    libxcb-xkb-dev
    libxkbcommon-dev
    libxkbcommon-x11-dev
    libxkbregistry-dev
    libxml2-dev
    libxxhash-dev
    meson
    ninja-build
    openssl
    psmisc
    python3-mako
    python3-markdown
    python3-markupsafe
    python3-pyquery
    python3-yaml
    qt6-base-dev
    rsync
    scdoc
    seatd
    spirv-tools
    unzip
    vulkan-utility-libraries-dev
    vulkan-validationlayers
    xdg-desktop-portal
    xwayland
)

# hyprland dependencies
hyprland_dep=(
    bc
    binutils
    libc6
    libcairo2-dev
    libdisplay-info3
    libdrm2
    libjpeg-dev
    libjxl-dev
    libmagic-dev
    libmuparser-dev
    libpixman-1-dev
    libpugixml-dev
    libre2-dev
    librsvg2-dev
    libspng-dev
    libtomlplusplus-dev
    libwebp-dev
    libzip-dev
    libpam0g-dev
    libxcursor-dev
    libxcb-errors-dev
    libudis86-dev
    libinotify-ocaml-dev
    qt6-declarative-dev
    qt6-base-private-dev
    qt6-wayland-dev
    qt6-wayland-private-dev
)

build_dep=(
    wlroots
)

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
LOG="Install-Logs/install-$(date +%d-%H%M%S)_dependencies.log"

clang_major_version() {
    if ! command -v clang >/dev/null 2>&1; then
        echo 0
        return
    fi
    clang --version 2>/dev/null | awk '
        /version/ {
            for (i = 1; i <= NF; i++) {
                if ($i == "version") {
                    split($(i+1), v, ".")
                    print v[1]
                    exit
                }
            }
        }'
}

llvm_repo_available_for_suite() {
    local suite="$1"
    curl -fsI "https://apt.llvm.org/${suite}/dists/llvm-toolchain-${suite}-21/InRelease" >/dev/null 2>&1
}

ensure_clang_21() {
    local current_major
    current_major="$(clang_major_version)"
    if [ "${current_major:-0}" -ge 21 ]; then
        echo "${INFO} clang ${current_major} already available; skipping LLVM 21 setup." | tee -a "$LOG"
        return 0
    fi
    if command -v clang-21 >/dev/null 2>&1 && command -v clang++-21 >/dev/null 2>&1; then
        echo "${INFO} clang-21 already installed." | tee -a "$LOG"
        return 0
    fi

    local detected_suite=""
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release || true
        detected_suite="${VERSION_CODENAME:-}"
    fi
    if [ -z "$detected_suite" ] && command -v lsb_release >/dev/null 2>&1; then
        detected_suite="$(lsb_release -sc 2>/dev/null || true)"
    fi

    local suites=()
    [ -n "$detected_suite" ] && suites+=("$detected_suite")
    suites+=(trixie bookworm sid unstable testing)

    local llvm_suite=""
    for suite in "${suites[@]}"; do
        llvm_repo_available_for_suite "$suite" && { llvm_suite="$suite"; break; }
    done

    if [ -z "$llvm_suite" ]; then
        echo "${WARN} LLVM 21 repo not available for detected/fallback suites; keeping distro clang (${current_major:-unknown})." | tee -a "$LOG"
        return 0
    fi

    echo "${INFO} Using apt.llvm.org suite '${llvm_suite}' for clang-21." | tee -a "$LOG"
    sudo install -d -m 0755 /etc/apt/keyrings >/dev/null 2>&1 || true
    if [ ! -f /etc/apt/keyrings/llvm.gpg ]; then
        if ! command -v gpg >/dev/null 2>&1; then
            sudo apt-get update 2>&1 | tee -a "$LOG"
            sudo apt-get install -y gnupg ca-certificates 2>&1 | tee -a "$LOG"
        fi
        curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
          | gpg --dearmor \
          | sudo tee /etc/apt/keyrings/llvm.gpg >/dev/null
    fi

    cat <<EOF | sudo tee /etc/apt/sources.list.d/llvm-21.list >/dev/null
deb [signed-by=/etc/apt/keyrings/llvm.gpg] https://apt.llvm.org/${llvm_suite}/ llvm-toolchain-${llvm_suite}-21 main
EOF

    sudo apt-get update 2>&1 | tee -a "$LOG"
    sudo apt-get install -y clang-21 clang-tools-21 lld-21 llvm-21 2>&1 | tee -a "$LOG"
}
# Preflight checks for common build issues
preflight_checks() {
    # Warn on invalid custom suites (e.g., tyson)
    if grep -RqsE '^[[:space:]]*deb .*tyson' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        echo "${WARN} Detected 'tyson' APT entries. These 404 and can break updates. Please remove/comment them." | tee -a "$LOG"
    fi

    # OpenGL headers/libs sanity (hard fail: required for builds)
    if [[ ! -f /usr/include/GL/gl.h ]]; then
        echo "${ERROR} Missing /usr/include/GL/gl.h (OpenGL headers). Install: mesa-common-dev libgl1-mesa-dev libglvnd-dev libopengl-dev libglx-dev" | tee -a "$LOG"
        exit 1
    fi
    if ! dpkg -L libopengl-dev 2>/dev/null | grep -q 'OpenGLConfig\.cmake'; then
        if ! cmake --find-package -DNAME=OpenGL -DCOMPILER_ID=GNU -DLANGUAGE=C -DMODE=EXIST >/dev/null 2>&1; then
            echo "${ERROR} OpenGL CMake package not found by CMake. Install: libopengl-dev libglvnd-dev" | tee -a "$LOG"
            exit 1
        fi
    fi
    local ldconfig_bin=""
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig_bin="$(command -v ldconfig)"
    elif [ -x /usr/sbin/ldconfig ]; then
        ldconfig_bin="/usr/sbin/ldconfig"
    elif [ -x /sbin/ldconfig ]; then
        ldconfig_bin="/sbin/ldconfig"
    fi
    if [ -z "$ldconfig_bin" ]; then
        echo "${WARN} ldconfig not found in PATH or /usr/sbin. Skipping libGL.so cache check." | tee -a "$LOG"
    else
        if ! "$ldconfig_bin" -p 2>/dev/null | grep -q 'libGL\.so'; then
            echo "${ERROR} libGL.so not found in ldconfig cache. Reinstall: libgl1-mesa-dev libglvnd-dev" | tee -a "$LOG"
            exit 1
        fi
    fi

    # Qt6 QML modules commonly required by hyprsysteminfo
    local qml_pkgs=(
        qml6-module-qtquick
        qml6-module-qtquick-controls
        qml6-module-qtquick-templates
        qml6-module-qtquick-layouts
        qml6-module-qtquick-window
        qml6-module-qtquick-shapes
        qml6-module-qt-labs-qmlmodels
    )
    local missing=()
    for p in "${qml_pkgs[@]}"; do
        if ! dpkg -s "$p" >/dev/null 2>&1; then
            missing+=("$p")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "${WARN} Missing Qt6 QML modules: ${missing[*]}" | tee -a "$LOG"
        echo "${NOTE} Install with: sudo apt install -y ${missing[*]}" | tee -a "$LOG"
    fi
}

# Installation of main dependencies
printf "\n%s - Installing ${SKY_BLUE}main dependencies....${RESET} \n" "${NOTE}"
preflight_checks

install_dep() {
    local pkg="$1"
    if [ "${DEBIAN_SUITE:-}" = "trixie" ]; then
        case "$pkg" in
        libxkbcommon-dev | libxkbcommon-x11-dev | libxkbregistry-dev | libgtk-3-dev | qt6-base-private-dev)
            install_package_target "$pkg" "trixie-backports"
            return
            ;;
        esac
    fi
    install_package "$pkg" "$LOG"
}

install_libdisplay_info() {
    local candidates=(libdisplay-info3 libdisplay-info2 libdisplay-info1 libdisplay-info-dev)
    local pkg
    for pkg in "${candidates[@]}"; do
        install_dep "$pkg"
        if dpkg -l | grep -q -w "$pkg"; then
            return 0
        fi
    done
    return 1
}

for PKG1 in "${dependencies[@]}" "${hyprland_dep[@]}"; do
    if [ "$PKG1" = "libdisplay-info3" ]; then
        install_libdisplay_info
    else
        install_dep "$PKG1"
    fi
done

printf "\n%.0s" {1..1}

for PKG1 in "${build_dep[@]}"; do
    build_dep "$PKG1" "$LOG"
done

# Hyprland v0.54+ benefits from LLVM/Clang 21.
# If apt.llvm.org does not publish the current codename, we safely keep distro clang.
ensure_clang_21

# Install Glaze (header-only) from bundled asset if not already present
# Hyprland's config serialization currently expects glaze >= 4.4; Debian may lag.
# If /usr/include/glaze is missing, install our vendor .deb and fix up deps.
if [ ! -d /usr/include/glaze ]; then
    echo "${INFO} ${YELLOW}Glaze${RESET} not detected. Installing from assets..." | tee -a "$LOG"
    if sudo dpkg -i assets/libglaze-dev_4.4.3-1_all.deb 2>&1 | tee -a "$LOG"; then
        sudo apt-get install -f -y 2>&1 | tee -a "$LOG"
        echo "${OK} ${YELLOW}libglaze-dev${RESET} installed from assets." | tee -a "$LOG"
    else
        echo "${WARN} Failed to install libglaze-dev from assets. You may install 'glaze' manually." | tee -a "$LOG"
    fi
fi

printf "\n%.0s" {1..2}
