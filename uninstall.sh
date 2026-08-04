#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# 💫 https://github.com/LinuxBeginnings 💫 #
# KooL Debian-Hyprland uninstall script #

clear

# Set some colors for output messages
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
# Set a high-contrast whiptail theme unless the user already provided one
if [ -z "${NEWT_COLORS:-}" ]; then
    export NEWT_COLORS='
root=white,black
border=white,black
window=white,black
shadow=black,black
title=yellow,black
button=black,lightgray
actbutton=white,blue
compactbutton=black,lightgray
textbox=white,black
acttextbox=white,black
entry=white,black
label=white,black
listbox=white,black
actlistbox=black,cyan
checkbox=white,black
actcheckbox=black,cyan
'
fi

printf "\n%.0s" {1..2}
echo -e "\e[35m
	╦╔═┌─┐┌─┐╦    ╦ ╦┬ ┬┌─┐┬─┐┬  ┌─┐┌┐┌┌┬┐
	╠╩╗│ ││ │║    ╠═╣└┬┘├─┘├┬┘│  ├─┤│││ ││ UNINSTALL
	╩ ╩└─┘└─┘╩═╝  ╩ ╩ ┴ ┴  ┴└─┴─┘┴ ┴┘└┘─┴┘ Debian
\e[0m"
printf "\n%.0s" {1..1}

# Show welcome message using whiptail with Yes/No options
whiptail --title "Debian-Hyprland KooL Dots Uninstall Script" --yesno \
"Hello! This script will uninstall KooL Hyprland packages and configs.

You can choose packages and directories you want to remove.
NOTE: This will remove configs from ~/.config

WARNING: After uninstallation, your system may become unstable.

Shall we Proceed?" 20 80

if [ $? -eq 1 ]; then
    echo "$INFO uninstall process canceled."
    exit 0
fi

# Detect whether a named package is installed via apt, source (/usr/local or /usr/bin),
# both, or not at all.  Echoes: apt | source | both | none
detect_pkg_install_method() {
    local pkg="$1"
    local is_apt=0 is_source=0

    dpkg -l "$pkg" 2>/dev/null | grep -q '^ii' && is_apt=1

    case "$pkg" in
        hyprland)
            { [ -f /usr/local/bin/hyprland ] || [ -f /usr/local/bin/Hyprland ]; } && is_source=1 ;;
        xdg-desktop-portal-hyprland)
            [ -f /usr/local/libexec/xdg-desktop-portal-hyprland ] && is_source=1 ;;
        wallust)
            [ -f /usr/local/bin/wallust ] && is_source=1 ;;
        waybar)
            [ -f /usr/local/bin/waybar ] && is_source=1 ;;
        swww)
            # installer builds awww -> /usr/bin/; legacy swww paths also checked
            { [ -f /usr/bin/awww ]          || [ -f /usr/local/bin/awww ]  \
              || [ -f /usr/bin/swww ]       || [ -f /usr/local/bin/swww ]; } && is_source=1 ;;
        rofi-wayland)
            [ -f /usr/local/bin/rofi ] && is_source=1 ;;
        wlogout)
            [ -f /usr/local/bin/wlogout ] && is_source=1 ;;
        hyprlock)
            [ -f /usr/local/bin/hyprlock ] && is_source=1 ;;
        hypridle)
            [ -f /usr/local/bin/hypridle ] && is_source=1 ;;
        hyprpaper)
            [ -f /usr/local/bin/hyprpaper ] && is_source=1 ;;
        hyprpicker)
            [ -f /usr/local/bin/hyprpicker ] && is_source=1 ;;
    esac

    if [[ $is_apt -eq 1 && $is_source -eq 1 ]]; then echo "both"
    elif [[ $is_apt -eq 1 ]]; then echo "apt"
    elif [[ $is_source -eq 1 ]]; then echo "source"
    else echo "none"
    fi
}

# Remove source-installed artifacts for a single named component.
# Returns 0 if something was removed, 1 if nothing was found.
remove_source_component() {
    local pkg="$1"
    local removed=0
    local f
    case "$pkg" in
        hyprland)
            for f in /usr/local/bin/hyprland /usr/local/bin/Hyprland \
                      /usr/local/bin/hyprctl /usr/local/bin/hyprpm \
                      /usr/local/share/wayland-sessions/hyprland.desktop \
                      /usr/local/share/hyprland; do
                if [ -e "$f" ]; then
                    echo "  Removing source artifact: $f"
                    sudo rm -rf "$f" && removed=1
                fi
            done
            for f in /usr/local/share/man/man1/hypr* /usr/local/share/man/man7/hypr*; do
                [ -e "$f" ] && sudo rm -f "$f" && removed=1
            done ;;
        xdg-desktop-portal-hyprland)
            for f in /usr/local/libexec/xdg-desktop-portal-hyprland \
                      "/usr/local/share/systemd/user/xdg-desktop-portal-hyprland.service" \
                      "/usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service" \
                      "/usr/local/share/xdg-desktop-portal/portals/hyprland.portal" \
                      "/usr/local/share/xdg-desktop-portal/hyprland.desktop"; do
                if [ -e "$f" ]; then
                    echo "  Removing source artifact: $f"
                    sudo rm -f "$f" && removed=1
                fi
            done ;;
        wallust)
            if [ -f /usr/local/bin/wallust ]; then
                echo "  Removing source artifact: /usr/local/bin/wallust"
                sudo rm -f /usr/local/bin/wallust && removed=1
            fi ;;
        waybar)
            if [ -f /usr/local/bin/waybar ]; then
                echo "  Removing source artifact: /usr/local/bin/waybar"
                sudo rm -f /usr/local/bin/waybar && removed=1
            fi ;;
        swww)
            for f in /usr/bin/awww /usr/bin/awww-daemon \
                      /usr/local/bin/awww /usr/local/bin/awww-daemon \
                      /usr/bin/swww /usr/bin/swww-daemon \
                      /usr/local/bin/swww /usr/local/bin/swww-daemon; do
                if [ -e "$f" ]; then
                    echo "  Removing source artifact: $f"
                    sudo rm -f "$f" && removed=1
                fi
            done ;;
        rofi-wayland)
            if [ -f /usr/local/bin/rofi ]; then
                echo "  Removing source artifact: /usr/local/bin/rofi"
                sudo rm -f /usr/local/bin/rofi && removed=1
                for f in /usr/local/share/man/man1/rofi*; do
                    [ -e "$f" ] && sudo rm -f "$f"
                done
                sudo rm -rf /usr/local/share/rofi 2>/dev/null || true
            fi ;;
        wlogout)
            if [ -f /usr/local/bin/wlogout ]; then
                echo "  Removing source artifact: /usr/local/bin/wlogout"
                sudo rm -f /usr/local/bin/wlogout && removed=1
            fi ;;
        hyprlock)
            if [ -f /usr/local/bin/hyprlock ]; then
                echo "  Removing source artifact: /usr/local/bin/hyprlock"
                sudo rm -f /usr/local/bin/hyprlock && removed=1
            fi ;;
        hypridle)
            if [ -f /usr/local/bin/hypridle ]; then
                echo "  Removing source artifact: /usr/local/bin/hypridle"
                sudo rm -f /usr/local/bin/hypridle && removed=1
            fi ;;
        hyprpaper)
            if [ -f /usr/local/bin/hyprpaper ]; then
                echo "  Removing source artifact: /usr/local/bin/hyprpaper"
                sudo rm -f /usr/local/bin/hyprpaper && removed=1
            fi ;;
        hyprpicker)
            if [ -f /usr/local/bin/hyprpicker ]; then
                echo "  Removing source artifact: /usr/local/bin/hyprpicker"
                sudo rm -f /usr/local/bin/hyprpicker && removed=1
            fi ;;
    esac
    return $((1 - removed))
}

# Function to remove selected packages on Debian/Ubuntu
remove_packages() {
    local selected_packages_file=$1
    local _method
    while read -r package; do
        _method="$(detect_pkg_install_method "$package")"
        if [ "$_method" = "none" ]; then
            echo "$INFO Package ${YELLOW}$package${RESET} not found (apt or source). Skipping."
            continue
        fi
        if [ "$_method" = "apt" ] || [ "$_method" = "both" ]; then
            echo "Removing apt package: $package"
            if ! sudo apt remove -y "$package"; then
                echo "$ERROR Failed to remove apt package: $package"
            else
                echo "$OK Successfully removed apt package: $package"
            fi
        fi
        if [ "$_method" = "source" ] || [ "$_method" = "both" ]; then
            echo "Removing source-installed artifacts for: $package"
            remove_source_component "$package" || true
        fi
    done < "$selected_packages_file"
}

# Function to remove selected directories
remove_directories() {
    local selected_dirs_file=$1
    while read -r dir; do
        pattern="$HOME/.config/$dir*"        
        # Loop through directories matching the pattern
        for dir_to_remove in $pattern; do
            if [ -d "$dir_to_remove" ]; then
                echo "Removing directory: $dir_to_remove"
                if ! rm -rf "$dir_to_remove"; then
                    echo "$ERROR Failed to remove directory: $dir_to_remove"
                else
                    echo "$OK Successfully removed directory: $dir_to_remove"
                fi
            else
                echo "$INFO Directory ${YELLOW}$dir_to_remove${RESET} not found. Skipping."
            fi
        done
    done < "$selected_dirs_file"
}

# Functions to handle source-installed (from /usr/local) components
remove_source_builds() {
    local found=0

    # Detect Hyprland under /usr/local
    local hypr_path
    hypr_path="$(command -v hyprland 2>/dev/null || true)"
    local hypr_real=""
    if [ -n "$hypr_path" ]; then
        hypr_real="$(readlink -f "$hypr_path" 2>/dev/null || echo "")"
        if [[ "$hypr_real" == /usr/local/* ]]; then
            found=1
        fi
    fi

    # Look for well-known source-installed files
    local PROBE_LIST=(
        /usr/local/bin/hyprland
        /usr/local/bin/hyprctl
        /usr/local/bin/hyprpm
        /usr/local/bin/hyprpaper
        /usr/local/bin/hyprlock
        /usr/local/bin/hypridle
        /usr/local/share/wayland-sessions/hyprland.desktop
        /usr/local/libexec/xdg-desktop-portal-hyprland
        /usr/local/bin/rofi
        /usr/local/bin/wallust
        /usr/bin/awww
        /usr/local/bin/waybar
        /usr/local/bin/wlogout
    )
    for p in "${PROBE_LIST[@]}"; do
        if [ -e "$p" ]; then
            found=1
            break
        fi
    done

    if [ $found -eq 0 ]; then
        echo "$INFO No source-built Hyprland components detected under /usr/local."
        return 0
    fi

    if ! whiptail --title "Remove source-built components" --yesno \
"One or more source-built components were detected (Hyprland, rofi, wallust, awww/swww, waybar, wlogout, etc.).\n\nRemove source-installed files (binaries, desktop entries, completions, portal, etc.)?" 13 80; then
        echo "$INFO Skipped removal of source-built components."
        return 0
    fi

    printf "\n%.0s" {1..1}
    printf "\n%s${SKY_BLUE}Removing source-installed Hyprland components${RESET}\n" "${NOTE}"

    local REMOVE_LIST=(
        /usr/local/bin/hyprland
        /usr/local/bin/Hyprland
        /usr/local/bin/hyprctl
        /usr/local/bin/hyprpm
        /usr/local/bin/hyprpaper
        /usr/local/bin/hyprlock
        /usr/local/bin/hypridle
        /usr/local/bin/hyprpicker
        /usr/local/bin/hyprshutdown
        /usr/local/bin/hyprsunset
        /usr/local/bin/ags
        /usr/local/bin/rofi
        /usr/local/bin/wallust
        /usr/bin/awww
        /usr/bin/awww-daemon
        /usr/local/bin/awww
        /usr/local/bin/awww-daemon
        /usr/local/bin/swww
        /usr/local/bin/swww-daemon
        /usr/local/bin/waybar
        /usr/local/bin/wlogout
        /usr/local/share/wayland-sessions/hyprland.desktop
        /usr/local/share/hyprland
        /usr/local/share/zsh/site-functions/_hyprctl
        /usr/local/share/bash-completion/completions/hyprctl
        /usr/local/share/fish/vendor_completions.d/hyprctl.fish
        /usr/local/libexec/xdg-desktop-portal-hyprland
        /usr/local/share/systemd/user/xdg-desktop-portal-hyprland.service
        /usr/local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service
        /usr/local/share/xdg-desktop-portal/portals/hyprland.portal
        /usr/local/share/xdg-desktop-portal/hyprland.desktop
        /usr/local/share/rofi
    )

    for item in "${REMOVE_LIST[@]}"; do
        if ls $item >/dev/null 2>&1; then
            echo "Removing $item"
            if ! sudo rm -rf $item; then
                echo "$ERROR Failed to remove: $item"
            else
                echo "$OK Removed: $item"
            fi
        fi
    done

    # Remove hypr* manpages if they exist
    for man in /usr/local/share/man/man1/hypr* /usr/local/share/man/man7/hypr*; do
        if [ -e "$man" ]; then
            echo "Removing $man"
            sudo rm -f "$man"
        fi
    done

    # Optionally remove locally built wlroots if detected under /usr/local
    local wlroots_prefix
    wlroots_prefix="$(pkg-config --variable=prefix wlroots 2>/dev/null || true)"
    if [[ "$wlroots_prefix" == "/usr/local" ]]; then
        if whiptail --title "Remove local wlroots" --yesno \
"wlroots appears to be installed under /usr/local (likely from source).\nRemove it as well?" 10 80; then
            local WLR_LIST=(
                /usr/local/lib/libwlroots*.so*
                /usr/local/include/wlr
                /usr/local/lib/pkgconfig/wlroots*.pc
                /usr/local/share/pkgconfig/wlroots*.pc
                /usr/local/share/man/man7/wlroots*.7
            )
            for item in "${WLR_LIST[@]}"; do
                if ls $item >/dev/null 2>&1; then
                    echo "Removing $item"
                    sudo rm -rf $item
                fi
            done
        fi
    fi
}

# Base package list: alternating name/description pairs
# The packages array is built dynamically below with [install method] annotations.
_pkg_base=(
    "btop"                        "resource monitor"
    "brightnessctl"               "brightnessctl"
    "cava"                        "Cross-platform Audio Visualizer"
    "cliphist"                    "clipboard manager"
    "fastfetch"                   "fastfetch"
    "ffmpegthumbnailer"           "FFmpeg Thumbnailer"
    "grim"                        "screenshot tool"
    "polkit-kde-agent-1"          "polkit agent"
    "imagemagick"                 "Image manipulation tool"
    "kitty"                       "kitty-terminal"
    "qt-style-kvantum"            "QT apps theming"
    "qt-style-kvantum-themes"     "QT apps theming"
    "libqt5quick5"                "QT apps theming"
    "libqt5qml5"                  "QT apps theming"
    "qt6-declarative-dev"         "QT apps theming"
    "mousepad"                    "simple text editor"
    "mpv"                         "multi-media player"
    "mpv-mpris"                   "mpv-plugin"
    "nvtop"                       "gpu resource monitor"
    "nwg-displays"                "display monitor configuration app"
    "nwg-look"                    "gtk settings app"
    "pamixer"                     "pamixer"
    "pavucontrol"                 "pavucontrol"
    "playerctl"                   "playerctl"
    "qalculate-gtk"               "calculator - QT"
    "qt5ct"                       "qt5ct"
    "qt6-svg"                     "qt6-svg"
    "qt6ct"                       "qt6ct"
    "slurp"                       "screenshot tool"
    "swappy"                      "screenshot tool"
    "sway-notification-center"    "notification agent"
    "swww"                        "wallpaper engine"
    "thunar"                      "File Manager"
    "thunar-archive-plugin"       "Archive Plugin"
    "thunar-volman"               "Volume Management"
    "tumbler"                     "Thumbnail Service"
    "wallust"                     "color palette generator"
    "waybar"                      "wayland bar"
    "wl-clipboard"                "clipboard manager"
    "wlogout"                     "logout menu"
    "xdg-desktop-portal-hyprland" "hyprland file picker"
    "yad"                         "dialog box"
    "yt-dlp"                      "video downloader"
    "xarchiver"                   "Archive Manager"
    "hyprland"                    "hyprland main package"
)

# Build packages array, annotating each description with the detected install method.
# Format: [apt], [source], [both], or [none] (not installed)
packages=()
for (( _pi=0; _pi<${#_pkg_base[@]}; _pi+=2 )); do
    _pname="${_pkg_base[$_pi]}"
    _pdesc="${_pkg_base[$_pi+1]}"
    _pmethod="$(detect_pkg_install_method "$_pname")"
    packages+=( "$_pname" "$_pdesc [$_pmethod]" "off" )
done

# Define the list of directories to choose from (with options_command tags)
directories=(
    "ags" "AGS desktop overview configuration" "off"
    "btop" "btop configuration" "off"
    "cava" "cava configuration" "off"
    "fastfetch" "fastfetch configuration" "off"
    "hypr" "main hyprland configuration" "off"
    "kitty" "kitty terminal configuration" "off"
    "Kvantum" "Kvantum-manager configuration" "off"
    "qt5ct" "qt5ct configuration" "off"
    "qt6ct" "qt6ct configuration" "off"
    "rofi" "rofi configuration" "off"
    "swappy" "swappy (screenshot tool) configuration" "off"
    "swaync" "swaync (notification agent) configuration" "off"
    "Thunar" "Thunar file manager configuration" "off"
    "wallust" "wallust (color pallete) configuration" "off"
    "waybar" "waybar configuration" "off"
    "wlogout" "wlogout (logout menu) configuration" "off"    
)

# Loop for package selection until user selects something or cancels
while true; do
    package_choices=$(whiptail --title "Select Packages to Uninstall" --checklist \
    "Select the packages you want to remove\nNOTE: 'SPACEBAR' to select & 'TAB' key to change selection" 35 90 25 \
    "${packages[@]}" 3>&1 1>&2 2>&3)

    # Check if the user canceled the operation
    if [ $? -eq 1 ]; then
        echo "$INFO uninstall process canceled."
        exit 0
    fi

    # If no packages are selected, ask again
    if [[ -z "$package_choices" ]]; then
        echo "$NOTE No packages selected. Please select at least one package."
    else
        echo "$package_choices" | tr -d '"' | tr ' ' '\n' > /tmp/selected_packages.txt
        echo "Packages to remove: $package_choices"
        break
    fi
done

# Loop for directory selection until user selects something or cancels
while true; do
    dir_choices=$(whiptail --title "Select Directories to Remove" --checklist \
    "Select the directories you want to remove\nNOTE: This will remove configs from ~/.config\n\nNOTE: 'SPACEBAR' to select & 'TAB' key to change selection" 28 90 18 \
    "${directories[@]}" 3>&1 1>&2 2>&3)

    # Check if the user canceled the operation
    if [ $? -eq 1 ]; then
        echo "$INFO uninstall process canceled."
        exit 0
    fi

    # If no directories are selected, ask again
    if [[ -z "$dir_choices" ]]; then
        echo "$NOTE No directories selected. Please select at least one directory."
    else
        # Save each selected directory to a new line in the temporary file
        echo "$dir_choices" | tr -d '"' | tr ' ' '\n' > /tmp/selected_directories.txt
        echo "Directories to remove: $dir_choices"
        break
    fi
done

# First confirmation - Warning about potential instability
if ! whiptail --title "Warning" --yesno \
"Warning: Removing these packages and directories may cause your system to become unstable and you may not be able to recover it.\n\nAre you sure you want to proceed?" \
10 80; then
    echo "$INFO uninstall process canceled."
    exit 0
fi

# Second confirmation - Final confirmation to proceed
if ! whiptail --title "Final Confirmation" --yesno \
"Are you absolutely sure you want to remove the selected packages and directories?\n\nWARNING! This action is irreversible." \
10 80; then
    echo "$INFO uninstall process canceled."
    exit 0
fi

printf "\n%.0s" {1..1}
printf "\n%s${SKY_BLUE}Attempting to remove selected packages${RESET}\n" "${NOTE}"
MAX_ATTEMPTS=2
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Remove packages
    remove_packages /tmp/selected_packages.txt

    # Check if any packages still need to be removed, retry if needed
    MISSING_PACKAGE_COUNT=0
    while read -r package; do
        if dpkg -l | grep -q "^ii  $package "; then
            MISSING_PACKAGE_COUNT=$((MISSING_PACKAGE_COUNT + 1))
        fi
    done < /tmp/selected_packages.txt

    if [ $MISSING_PACKAGE_COUNT -gt 0 ]; then
        ATTEMPT=$((ATTEMPT + 1))
        echo "Attempt #$ATTEMPT failed, retrying..."
    else
        break
    fi
done


printf "\n%.0s" {1..1}
printf "\n%s${SKY_BLUE}Checking for source-built components under /usr/local${RESET}\n" "${NOTE}"
remove_source_builds

printf "\n%.0s" {1..1}
printf "\n%s${SKY_BLUE}Attempting to remove selected directories${RESET}\n" "${NOTE}"
remove_directories /tmp/selected_directories.txt

printf "\n%.0s" {1..1}
echo -e "$MAGENTA Hyprland and related components have been uninstalled.$RESET"
echo -e "$YELLOW It is recommended to reboot your system now.$RESET"
printf "\n%.0s" {1..1}