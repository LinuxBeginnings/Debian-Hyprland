#!/bin/bash
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hyprland-Dots to download a specific release #

# Resolve reference: prefer $DOTFILES_REF, else latest release tag, else 'main'
DOTFILES_REF="${DOTFILES_REF:-}"
RESOLVED_REF=""
if [ -n "$DOTFILES_REF" ]; then
  RESOLVED_REF="$DOTFILES_REF"
else
  latest_status=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/LinuxBeginnings/Hyprland-Dots/releases/latest")
  if [ "$latest_status" = "200" ]; then
    latest_json=$(curl -s "https://api.github.com/repos/LinuxBeginnings/Hyprland-Dots/releases/latest")
    RESOLVED_REF=$(echo "$latest_json" | grep -m1 '"tag_name"' | cut -d '"' -f 4)
  fi
  [ -z "$RESOLVED_REF" ] && RESOLVED_REF="main"
fi
# Use filesystem-safe filename fragment for the tarball
safe_ref=$(echo "$RESOLVED_REF" | tr '/:' '__')

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

printf "${NOTE} Downloading / Checking for existing Hyprland-Dots-${safe_ref}.tar.gz...\n"

# Check if the specific release tarball exists
if [ -f "Hyprland-Dots-${safe_ref}.tar.gz" ]; then
    printf "${NOTE} Hyprland-Dots-${safe_ref}.tar.gz found.\n"
    echo -e "${OK} Hyprland-Dots-${safe_ref}.tar.gz is already downloaded."
    exit 0
fi

printf "${NOTE} Downloading Hyprland-Dots (${RESOLVED_REF}) source...\n"

# Determine tarball URL for resolved ref (works for tags and branches)
tarball_url="https://api.github.com/repos/LinuxBeginnings/Hyprland-Dots/tarball/${RESOLVED_REF}"
# Quick reachability check
tar_status=$(curl -s -o /dev/null -w "%{http_code}" -L "$tarball_url")
if [ "$tar_status" != "200" ]; then
    echo -e "${ERROR} Unable to download tarball for ref ${RESOLVED_REF} (HTTP $tar_status)." 2>&1 | tee -a "../Install-Logs/install-$(date +'%d-%H%M%S')_dotfiles.log"
    exit 1
fi

# Download the specific release source code tarball to the current directory
if curl -L "$tarball_url" -o "Hyprland-Dots-${safe_ref}.tar.gz"; then
    # Extract the contents of the tarball
    tar -xzf "Hyprland-Dots-${safe_ref}.tar.gz" || exit 1

# Delete existing Hyprland-Dots
rm -rf LinuxBeginnings-Hyprland-Dots

# Identify the extracted directory
extracted_directory=$(tar -tf "Hyprland-Dots-${safe_ref}.tar.gz" | grep -o '^[^/]\+' | uniq)

# Rename the extracted directory to LinuxBeginnings-Hyprland-Dots
mv "$extracted_directory" LinuxBeginnings-Hyprland-Dots || exit 1

cd "LinuxBeginnings-Hyprland-Dots" || exit 1

    # Set execute permission for copy.sh and execute it
    chmod +x copy.sh
    ./copy.sh

echo -e "${OK} Hyprland-Dots (${RESOLVED_REF}) downloaded, extracted, and processed successfully. Check LinuxBeginnings-Hyprland-Dots directory for more detailed install logs" 2>&1 | tee -a "../Install-Logs/install-$(date +"%d-%H%M%S")_dotfiles.log"
else
echo -e "${ERROR} Failed to download Hyprland-Dots (${RESOLVED_REF})." 2>&1 | tee -a "../Install-Logs/install-$(date +"%d-%H%M%S")_dotfiles.log"
    exit 1
fi

clear
