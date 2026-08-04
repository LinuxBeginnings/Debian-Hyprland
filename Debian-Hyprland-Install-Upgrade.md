# Debian-Hyprland Install & Upgrade Guide

This guide covers the enhanced installation and upgrade workflows for KooL's Debian-Hyprland project, including new automation features, centralized version management, and dry-run capabilities.

## Table of Contents

1. [Overview](#overview)
2. [New Features](#new-features)
3. [Flags Reference](#flags-reference)
4. [Debian 13 (Trixie) Compatibility Mode](#debian-13-trixie-compatibility-mode)
5. [Debian Package Mode](#debian-package-mode)
6. [Central Version Management](#central-version-management)
7. [Installation Methods](#installation-methods)
8. [Upgrade Workflows](#upgrade-workflows)
9. [Dry-Run Testing](#dry-run-testing)
10. [Log Management](#log-management)
11. [Advanced Usage](#advanced-usage)
12. [Troubleshooting](#troubleshooting)

## Overview

The Debian-Hyprland project now includes enhanced automation and management tools while maintaining backward compatibility with the original install.sh script. The key additions are:

- **Centralized version management** via `hypr-tags.env`
- **Automated dependency ordering** for Hyprland 0.51.x requirements
- **Dry-run compilation testing** without system modifications
- **Selective component updates** via `update-hyprland.sh`
- **GitHub latest tag fetching** for automatic version discovery
- **Debian package mode** for installing Hyprland directly from Debian repos (no source build required)
- **Version visibility** — compare Debian candidate, local tag, and upstream release before choosing a build mode

## New Features

### Enhanced install.sh

The original install.sh script now includes:

- **Tag consistency**: Reads `hypr-tags.env` and exports version variables to all modules
- **Automatic wayland-protocols**: Installs wayland-protocols from source (≥1.45) before Hyprland
- **Robust dependency ordering**: Ensures prerequisites are built in the correct sequence

### New Scripts

#### update-hyprland.sh

A focused tool for managing and building just the Hyprland stack:

```bash
chmod +x ./update-hyprland.sh
./update-hyprland.sh --help  # View all options
```

Key flags:

- --fetch-latest: pull latest release tags from GitHub
- --force-update: override pinned values in hypr-tags.env (equivalent to FORCE=1)
- --dry-run / --install: compile-only or compile+install
- --only / --skip: limit which modules run
- --package-cleanup: purge Debian-packaged Hyprland stack before building
- --build-trixie / --no-trixie: enable/disable Debian 13 (trixie) compatibility mode (auto-detected by default)
- --mode auto|source|debian: select operation mode (default: auto → Debian package mode)
- --source / --deb-pkg: non-interactive aliases for source or Debian package mode
- --show-versions: print Debian candidate, local tag, and upstream Hyprland versions
- --debian-remove: remove Debian Hyprland packages and exit
- --no-fetch: skip auto-fetching latest tags during --install
- --bundled / --system: build with bundled or system hypr* libraries (default: --system)

#### dry-run-build.sh

A testing tool that compiles components without installing:

```bash
chmod +x ./dry-run-build.sh
./dry-run-build.sh --help  # View all options
```

#### wayland-protocols-src.sh

A new module that builds wayland-protocols from source to satisfy Hyprland 0.51.x requirements.

## Flags Reference

This repo provides several "control flags" that affect how the stack is built. These are intentionally consistent across tools.

### update-hyprland.sh flags

- `--install` / `--dry-run`: compile+install vs compile-only
- `--only <list>` / `--skip <list>`: run a subset of modules
- `--with-deps`: install build dependencies (via `00-dependencies.sh`) before building
- `--fetch-latest`: query GitHub Releases and refresh `hypr-tags.env` tags
- `--force-update`: override pinned values in `hypr-tags.env` (equivalent to `FORCE=1`)
- `--restore`: restore the most recent `hypr-tags.env` backup before building
- `--set K=V [...]`: set one or more version tags (e.g., `--set HYPRLAND=v0.53.0`)
- `--package-cleanup`: purge Debian Hyprland packages before building
- `--build-trixie` / `--no-trixie`: enable/disable Debian 13 compatibility mode
- `--mode MODE`: select operation mode — `auto` (default), `source`, or `debian`
- `--source`: alias for `--mode source` (non-interactive source build)
- `--deb-pkg` / `--packages`: alias for `--mode debian` (non-interactive Debian package install)
- `--show-versions` / `--versions`: query and print Debian candidate, local `hypr-tags.env`, and upstream Hyprland versions, then exit
- `--debian-install`: install Hyprland stack from Debian repos and skip source build
- `--debian-remove`: remove Debian Hyprland stack packages and exit
- `--no-fetch`: skip auto-fetching latest tags when running `--install`
- `--bundled`: build Hyprland with bundled hypr* subprojects instead of system-installed libs
- `--system`: prefer system-installed hypr* libraries (default)
- `--minimal`: build only the minimal prerequisite stack before Hyprland
- `--via-helper`: delegate dry-run to `dry-run-build.sh` for a compact summary view

Environment variables:
- `FORCE=1`: equivalent to `--force-update`
- `HYPR_AUTO_MODE_POLICY`: controls `--mode auto` behavior — `debian-default` (default, selects Debian package mode silently) or `menu` (interactive prompt comparing Debian/local/upstream versions)

Notes:
- When trixie mode is enabled, `update-hyprland.sh` exports `HYPR_BUILD_TRIXIE=1` and forwards `--build-trixie` to module scripts.
- `--package-cleanup` removes Debian-provided Hyprland packages to avoid mixed versions (Hyprland, hyprutils/lang/graphics/cursor/wire, aquamarine, qt support, guiutils, tools/apps like hypridle/lock/picker/paper/sunset/launcher/systeminfo, hyprpm/hyprctl, and xdg-desktop-portal-hyprland).
- In source mode with `--install`, `--package-cleanup` is enabled automatically to prevent mixed Debian/source installs.
- In source mode with `--install`, tags are auto-fetched before building unless `--no-fetch` is set.

### install.sh flags

- `--preset <file>`: run unattended-ish using preset choices
- `--build-trixie` / `--no-trixie`: enable/disable Debian 13 compatibility mode

You can also force via env:

```bash
HYPR_BUILD_TRIXIE=1 ./install.sh
```

### refresh-hypr-tags.sh flags

- `--get-latest` / `--fetch-latest`: refresh tags to latest GitHub releases (aliases; the script always fetches latest)
- `--force-update` / `--force`: force-override pinned values in `hypr-tags.env`

Equivalent env form:

```bash
FORCE=1 ./refresh-hypr-tags.sh
# or
./refresh-hypr-tags.sh --force-update
```

Optional environment variable to avoid GitHub API rate limits:

```bash
GITHUB_TOKEN=<token> ./refresh-hypr-tags.sh
# GH_TOKEN is also accepted
```

In interactive sessions the script shows a diff of planned changes and prompts for confirmation before writing. Non-interactive runs write immediately.

## Debian 13 (Trixie) Compatibility Mode

Newer Hyprland versions (0.53.x+) may require source-level compatibility shims on Debian 13 (trixie) due to toolchain / standard-library feature gaps.

- Default behavior is **auto-detect** (via `/etc/os-release`): if `ID=debian` and `VERSION_CODENAME=trixie`, compatibility mode turns on.
- You can force it on/off:

```bash
# Force ON
./update-hyprland.sh --build-trixie --install

# Force OFF
./update-hyprland.sh --no-trixie --install
```

## Debian Package Mode

`update-hyprland.sh` now supports installing Hyprland directly from Debian repositories in addition to building from source. **Debian package mode is the default** when no mode flag is given.

### Mode Selection

- `--mode debian` / `--deb-pkg` / `--packages`: install from Debian repos (no source build)
- `--mode source` / `--source`: build from source using `hypr-tags.env` versions
- `--mode auto` (default): behavior controlled by `HYPR_AUTO_MODE_POLICY`
  - `debian-default` (default): silently selects Debian package mode
  - `menu`: shows an interactive prompt with Debian candidate, local tag, and upstream version

Set `HYPR_AUTO_MODE_POLICY=menu` in your environment to get the interactive version-comparison prompt on every run.

### Checking Versions Before Choosing

```bash
# Print Debian candidate, local hypr-tags.env tag, and upstream latest, then exit
./update-hyprland.sh --show-versions
```

### Installing via Debian Package Mode

```bash
# Default install (Debian package mode)
./update-hyprland.sh --install

# Explicit Debian package install
./update-hyprland.sh --deb-pkg --install
```

On **Trixie**, the script automatically adds `trixie-backports` if not already configured.

### Installing via Source Mode

```bash
# Source build using current hypr-tags.env
./update-hyprland.sh --source --install

# Source build after fetching latest tags
./update-hyprland.sh --source --fetch-latest --install
```

Switching to source mode automatically purges any Debian-installed Hyprland packages to avoid mixed-version conflicts.

### Removing Debian Hyprland Packages

```bash
./update-hyprland.sh --debian-remove
```

## Central Version Management

### hypr-tags.env

This file contains version tags for all Hyprland components:

```bash
# Core stack tags (example — actual values updated by refresh-hypr-tags.sh)
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
HYPRWIRE_TAG=main
WAYLAND_PROTOCOLS_TAG=1.46
XDPH_TAG=v1.3.12
```

`HYPRWIRE_TAG` is always pinned to `main` (no versioned releases). After running `refresh-hypr-tags.sh`, additional app-specific tags are also tracked and updated: `HYPRIDLE_TAG`, `HYPRLOCK_TAG`, `HYPRPICKER_TAG`, `HYPRSUNSET_TAG`, `HYPRLAUNCHER_TAG`, `HYPRSYSTEMINFO_TAG`, and others.

### Refreshing tags (latest releases)

You can refresh `hypr-tags.env` to the latest GitHub release tags:

```bash
# Update only keys set to auto/latest (or unset)
./refresh-hypr-tags.sh --get-latest

# Force-override pinned keys
FORCE=1 ./refresh-hypr-tags.sh --get-latest
# or
./refresh-hypr-tags.sh --force-update
```

### Version Override Priority

1. Environment variables (exported)
2. hypr-tags.env file values
3. Default hardcoded values in each module

## Installation Methods

### Method 1: Original Full Installation

```bash
# Standard installation with all components
chmod +x install.sh
./install.sh
```

This method now automatically:

- Loads versions from `hypr-tags.env`
- Installs wayland-protocols from source before Hyprland
- Maintains proper dependency ordering

### Method 2a: Hyprland Stack from Debian Repos (default)

```bash
# Install from Debian repos (default mode)
./update-hyprland.sh --install
# or explicitly:
./update-hyprland.sh --deb-pkg --install
```

### Method 2b: Hyprland Stack from Source

```bash
# Build from source using current hypr-tags.env
./update-hyprland.sh --source --install
```

Switching from Debian packages to source mode automatically purges the Debian packages first. To do this manually before a source build:

```bash
./update-hyprland.sh --debian-remove
./update-hyprland.sh --source --install
```

### Method 3: Fresh Source Installation with Latest Versions

```bash
# Fetch latest GitHub release tags and install from source
./update-hyprland.sh --source --fetch-latest --install

# Override all pinned values (including manually pinned ones):
./update-hyprland.sh --source --fetch-latest --force-update --install
```

### Method 4: Preset-Based Installation

```bash
# Use preset file for automated choices
./install.sh --preset ./preset.sh
```

## Upgrade Workflows

Quick link: [Upgrade 0.49/0.50.x → 0.51.1](#upgrade-049050x--0511)

### Upgrading to Latest Hyprland Release

#### Option A: Automatic Discovery (source build)

```bash
# Fetch latest tags and install from source (respects pins in hypr-tags.env)
./update-hyprland.sh --source --fetch-latest --install

# Force-override all pinned values
./update-hyprland.sh --source --fetch-latest --force-update --install
```

#### Option B: Specific Version (source build)

```bash
# Set specific Hyprland version and build from source
./update-hyprland.sh --source --set HYPRLAND=v0.51.1 --install
```

#### Option C: Test Before Installing

```bash
# Compile-test first (source mode), then install if successful
./update-hyprland.sh --source --fetch-latest --dry-run
# If successful:
./update-hyprland.sh --source --install
```

### Upgrading Individual Components

```bash
# Update only core libraries from source (often needed for new Hyprland versions)
./update-hyprland.sh --source --fetch-latest --install --only hyprutils,hyprlang

# Update aquamarine specifically
./update-hyprland.sh --source --set AQUAMARINE=v0.9.3 --install --only aquamarine
```

### Selective Updates

```bash
# Install everything except Qt components (source mode)
./update-hyprland.sh --source --install --skip hyprland-qt-support,hyprland-qtutils

# Install only specific components
./update-hyprland.sh --source --install --only hyprland,aquamarine
```

### Upgrade: 0.49/0.50.x ➜ 0.51.1

If you're currently on Hyprland 0.49 or 0.50.x, you can upgrade directly to 0.51.1 without a full reinstall.

Recommended path:

```bash
# Ensure hypr-tags.env pins the target version (skip if already v0.51.1)
./update-hyprland.sh --set HYPRLAND=v0.51.1

# Upgrade Hyprland from source (prerequisites are auto-included and ordered)
./update-hyprland.sh --source --install --only hyprland
```

Notes:

- The command will automatically ensure and run, as needed: wayland-protocols-src, hyprland-protocols, hyprutils, hyprlang, aquamarine, then hyprland.
- Full install via install.sh is not required for this upgrade unless you also want to install/refresh optional modules (e.g., SDDM, Bluetooth, Thunar, AGS, dotfiles) or you're recovering from a failed/partial setup.
- Optional: add --with-deps to re-run dependency installation first:

```bash
./update-hyprland.sh --source --with-deps --install --only hyprland
```

- You can dry-run first to validate:

```bash
./update-hyprland.sh --source --dry-run --only hyprland
```

## Dry-Run Testing

### Why Use Dry-Run?

- Test compilation compatibility before installing
- Validate version combinations
- Debug build issues without system changes
- CI/CD pipeline integration

### Basic Dry-Run Usage

Dry-run tests are source-mode operations. Add `--source` to ensure the compile test runs rather than checking Debian package availability:

```bash
# Test current tag configuration
./update-hyprland.sh --source --dry-run

# Test with latest GitHub releases
./update-hyprland.sh --source --fetch-latest --dry-run

# Test specific version
./update-hyprland.sh --source --set HYPRLAND=v0.51.1 --dry-run
```

### Advanced Dry-Run Testing

```bash
# Use alternative summary format
./update-hyprland.sh --via-helper

# Test with dependencies installation
./dry-run-build.sh --with-deps

# Test only specific components
./dry-run-build.sh --only hyprland,aquamarine
```

### Dry-Run Limitations

- **Dependencies still install**: apt operations run to ensure compilation succeeds
- **pkg-config requirements**: Some components need system-installed prerequisites
- **No system changes**: No files installed to /usr/local or /usr

## Log Management
## Build Artifacts & Cleanup

All source clones and build outputs now live under `~/Debian-Hyprland/build/`:

- **Sources:** `build/src/<project>`
- **Build output:** `build/<project>`

This keeps the repo root clean. To remove all build artifacts:

```bash
rm -rf ~/Debian-Hyprland/build
```

Note: This only removes build artifacts and downloaded sources; it does not uninstall anything from your system.

### Log Location

All build activities generate timestamped logs in:

```
Install-Logs/
├── 01-Hyprland-Install-Scripts-YYYY-MM-DD-HHMMSS.log  # Main install log
├── install-DD-HHMMSS_module-name.log                   # Per-module logs
├── build-dry-run-YYYY-MM-DD-HHMMSS.log                # Dry-run summary
└── update-hypr-YYYY-MM-DD-HHMMSS.log                  # Update tool summary
```

### Log Analysis

```bash
# View most recent install log
ls -t Install-Logs/*.log | head -1 | xargs less

# Check for errors in specific module
grep -i error Install-Logs/install-*hyprland*.log

# View dry-run summary
cat Install-Logs/build-dry-run-*.log
```

### Log Retention

- Logs accumulate over time for historical reference
- Manual cleanup recommended periodically:

```bash
# Keep only logs from last 30 days
find Install-Logs/ -name "*.log" -mtime +30 -delete
```

## Advanced Usage

### Tag Management

#### Force Update All Tags

```bash
# Override pinned values in hypr-tags.env to the latest releases
./update-hyprland.sh --source --fetch-latest --force-update --dry-run
# Install if the dry-run succeeds
./update-hyprland.sh --source --force-update --install
```

#### Backup and Restore

```bash
# Tags are automatically backed up on changes
# Restore most recent backup
./update-hyprland.sh --source --restore --dry-run
```

#### Multiple Version Sets

```bash
# Save current configuration
cp hypr-tags.env hypr-tags-stable.env

# Try experimental versions
./update-hyprland.sh --source --fetch-latest --dry-run

# Restore stable if needed
cp hypr-tags-stable.env hypr-tags.env
```

### Environment Integration

#### Custom PKG_CONFIG_PATH (source builds)

```bash
# Ensure /usr/local takes precedence
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:${PKG_CONFIG_PATH:-}"
./update-hyprland.sh --source --install
```

#### Parallel Builds

```bash
# Control build parallelism (default: all cores)
export MAKEFLAGS="-j4"
./update-hyprland.sh --source --install
```

### Development Workflow

#### Testing New Releases

```bash
# 1. Create test environment
cp hypr-tags.env hypr-tags.backup

# 2. Compile-test new version from source
./update-hyprland.sh --source --set HYPRLAND=v0.52.0 --dry-run

# 3. Install from source if successful
./update-hyprland.sh --source --install

# 4. Rollback if issues
./update-hyprland.sh --source --restore --install
```

#### Component Development

```bash
# Install dependencies only
./update-hyprland.sh --source --with-deps --dry-run

# Manual module testing
DRY_RUN=1 ./install-scripts/hyprland.sh

# Check logs for specific module
tail -f Install-Logs/install-*hyprland*.log
```

## Troubleshooting

### Common Issues

#### CMake Configuration Fails

**Symptoms**: "Package dependency requirement not satisfied"

**Solutions**:

```bash
# Install missing prerequisites from source
./update-hyprland.sh --source --install --only wayland-protocols-src,hyprutils,hyprlang

# Clear build cache
rm -rf hyprland aquamarine hyprutils hyprlang

# Retry installation
./update-hyprland.sh --source --install --only hyprland
```

#### Compilation Errors

**Symptoms**: "too many errors emitted"

**Solutions**:

```bash
# Update core dependencies first
./update-hyprland.sh --source --fetch-latest --install --only hyprutils,hyprlang

# Check for API mismatches in logs
grep -A5 -B5 "error:" Install-Logs/install-*hyprland*.log
```

#### Tag Not Found

**Symptoms**: "Remote branch X not found"

**Solutions**:

```bash
# Check available tags
git ls-remote --tags https://github.com/hyprwm/Hyprland

# Use confirmed existing tag
./update-hyprland.sh --source --set HYPRLAND=v0.50.1 --install
```
#### GUI Apps via pkexec Fail (Wayland)

**Symptoms**: Password prompt appears but app fails to launch; errors like “Authorization required, but no authorization protocol specified” or “cannot open display”.

**Solutions**:

```bash
pkexec env -u DISPLAY -u XAUTHORITY \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
  GDK_BACKEND=wayland \
  QT_QPA_PLATFORM=wayland \
  <app>
```

**Notes**:
- Ensure a Polkit agent is installed and running (this installer includes `xfce-polkit`).

### Debug Steps

1. **Check system compatibility**:

    ```bash
    # Verify Debian version
    cat /etc/os-release

    # Ensure deb-src enabled
    grep -rE "^[[:space:]]*(deb-src|Types:.*deb-src)" /etc/apt/sources.list /etc/apt/sources.list.d/
    ```

2. **Verify environment**:

    ```bash
    # Check current tags
    cat hypr-tags.env

    # Test dry-run first (source mode)
    ./update-hyprland.sh --source --dry-run --only hyprland
    ```

3. **Analyze logs**:

    ```bash
    # Most recent errors
    grep -i "error\|fail" Install-Logs/*.log | tail -20

    # Module-specific issues
    ls -la Install-Logs/install-*[component]*.log
    ```

### Getting Help

1. **Check logs**: Always review Install-Logs/ for detailed error information
2. **Test dry-run**: Use --dry-run to validate before installing
3. **Community support**: Submit issues with relevant log excerpts
4. **Documentation**: Refer to main project README.md for base requirements

## Migration from Previous Versions

### Existing Installations

The new tools work alongside existing installations:

```bash
# Update via Debian packages (default)
./update-hyprland.sh --install

# Update via source build
./update-hyprland.sh --source --install

# Test source build without affecting current system
./update-hyprland.sh --source --dry-run
```

### Converting to Tag Management

```bash
# Current versions are saved to hypr-tags.env automatically
# Verify with:
cat hypr-tags.env

# hyprland-guiutils compatibility:
# - older tags generally use Qt6 dependency path
# - newer tags may use pixman/libdrm/libxkbcommon path
# if you pin HYPRLAND_GUIUTILS_TAG and builds fail, verify that tag's upstream deps

# Modify versions as needed:
./update-hyprland.sh --set HYPRLAND=v0.51.1
```

The enhanced workflow provides better control, testing capabilities, and automation while maintaining full compatibility with the original installation process.
