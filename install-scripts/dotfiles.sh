#!/bin/bash
# 💫 https://github.com/LinuxBeginnings 💫 #
# Hyprland-Dots to download a specific release #

# Define the specific release version to download
specific_version="v2.3.16"
#specific_version="v2.3.3-Deb-Untu-Hyprland-0.41.2"

## WARNING: DO NOT EDIT BEYOND THIS LINE IF YOU DON'T KNOW WHAT YOU ARE DOING! ##

source "$(dirname "$(readlink -f "$0")")/Global_functions.sh"

printf "${NOTE} Downloading / Checking for existing Hyprland-Dots-${specific_version}.tar.gz...\n"

# Check if the specific release tarball exists
if [ -f "Hyprland-Dots-${specific_version}.tar.gz" ]; then
    printf "${NOTE} Hyprland-Dots-${specific_version}.tar.gz found.\n"
    echo -e "${OK} Hyprland-Dots-${specific_version}.tar.gz is already downloaded."
    exit 0
fi

printf "${NOTE} Downloading the Hyprland-Dots-${specific_version} source code release...\n"

# Resolve tarball URL for the specific tag, with fallback if no Release object exists
status=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/LinuxBeginnings/Hyprland-Dots/releases/tags/${specific_version}")
if [ "$status" = "200" ]; then
    release_info=$(curl -s "https://api.github.com/repos/LinuxBeginnings/Hyprland-Dots/releases/tags/${specific_version}")
    tarball_url=$(echo "$release_info" | grep "tarball_url" | cut -d '"' -f 4)
else
    tarball_url="https://api.github.com/repos/LinuxBeginnings/Hyprland-Dots/tarball/${specific_version}"
fi

# Validate tarball URL
if [ -z "$tarball_url" ]; then
    echo -e "${ERROR} Unable to determine tarball URL for ${specific_version}." 2>&1 | tee -a "../Install-Logs/install-$(date +'%d-%H%M%S')_dotfiles.log"
    exit 1
fi

# Download the specific release source code tarball to the current directory
if curl -L "$tarball_url" -o "Hyprland-Dots-${specific_version}.tar.gz"; then
    # Extract the contents of the tarball
    tar -xzf "Hyprland-Dots-${specific_version}.tar.gz" || exit 1

# Delete existing Hyprland-Dots
rm -rf LinuxBeginnings-Hyprland-Dots

# Identify the extracted directory
extracted_directory=$(tar -tf "Hyprland-Dots-${specific_version}.tar.gz" | grep -o '^[^/]\+' | uniq)

# Rename the extracted directory to LinuxBeginnings-Hyprland-Dots
mv "$extracted_directory" LinuxBeginnings-Hyprland-Dots || exit 1

cd "LinuxBeginnings-Hyprland-Dots" || exit 1

    # Set execute permission for copy.sh and execute it
    chmod +x copy.sh
    ./copy.sh

echo -e "${OK} Hyprland-Dots-${specific_version} release downloaded, extracted, and processed successfully. Check LinuxBeginnings-Hyprland-Dots directory for more detailed install logs" 2>&1 | tee -a "../Install-Logs/install-$(date +'%d-%H%M%S')_dotfiles.log"
else
    echo -e "${ERROR} Failed to download Hyprland-Dots-${specific_version} release." 2>&1 | tee -a "../Install-Logs/install-$(date +'%d-%H%M%S')_dotfiles.log"
    exit 1
fi

clear
