#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# pkg-config preflight guard for the source-built Hypr* stack.
#
# Source builds install their pkg-config metadata into /usr/local, which is part
# of pkg-config's *default* search path. If the libraries are later removed
# (e.g. after switching to Debian package mode) while the .pc files survive,
# CMake configure still succeeds and the final link fails with:
#     /usr/bin/ld: cannot find -lhyprutils: No such file or directory
# This preflight reports (or prunes) that dangling metadata up front.
#
# Usage:
#   install-scripts/pkgconfig-preflight.sh           # report dangling metadata
#   install-scripts/pkgconfig-preflight.sh --prune   # delete dangling .pc files
#   install-scripts/pkgconfig-preflight.sh --strict  # exit 1 when problems found
#
# Exit status: 0 unless --strict is used and dangling metadata was found.

set -uo pipefail

PC_DIRS=(
    /usr/local/lib/pkgconfig
    /usr/local/share/pkgconfig
)

# Directories the linker searches by default (plus /usr/local/lib) so a library
# provided by the distro is never reported as missing.
DEFAULT_LIB_DIRS=(
    /usr/local/lib
    /usr/lib/x86_64-linux-gnu
    /usr/lib
    /lib/x86_64-linux-gnu
    /lib
)

PRUNE=0
STRICT=0

for arg in "$@"; do
    case "$arg" in
    --prune) PRUNE=1 ;;
    --strict) STRICT=1 ;;
    -h | --help)
        sed -n '/^# Usage:/,/^# Exit status:/p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "pkg-config preflight: unknown argument '$arg'" >&2
        exit 2
        ;;
    esac
done

command -v pkg-config >/dev/null 2>&1 || exit 0

# A linker `-l<name>` needs an unversioned lib<name>.so or a lib<name>.a;
# a versioned lib<name>.so.N alone does not satisfy it.
lib_available() {
    local name="$1"
    shift
    local dir
    for dir in "$@"; do
        [ -n "$dir" ] || continue
        if [ -e "$dir/lib${name}.so" ] || [ -e "$dir/lib${name}.a" ]; then
            return 0
        fi
    done
    return 1
}

found=0
pruned=0

for pc_dir in "${PC_DIRS[@]}"; do
    [ -d "$pc_dir" ] || continue
    for pc in "$pc_dir"/*.pc; do
        [ -f "$pc" ] || continue
        name="$(basename "$pc" .pc)"

        # Resolve this file's own libdir (handles ${prefix}/lib style variables).
        # Prepend the file's own directory so the .pc under inspection is the one
        # that gets resolved, while Requires: entries still resolve normally.
        libdir="$(PKG_CONFIG_PATH="$pc_dir:${PKG_CONFIG_PATH:-}" pkg-config --variable=libdir "$name" 2>/dev/null || true)"
        if [ -z "$libdir" ]; then
            # No libdir to compare against (or pkg-config refuses to parse the file,
            # which fails loudly at configure time anyway): nothing to judge here.
            continue
        fi

        # Only the libs declared by *this* file are checked; Requires: entries are
        # reported by the file that owns them.
        libs="$(sed -n 's/^Libs:[[:space:]]*//p' "$pc" 2>/dev/null | tr ' ' '\n' | sed -n 's/^-l//p' | sort -u)"
        [ -n "$libs" ] || continue

        missing=""
        for lib in $libs; do
            if ! lib_available "$lib" "$libdir" "${DEFAULT_LIB_DIRS[@]}"; then
                missing="${missing:+$missing }$lib"
            fi
        done
        [ -n "$missing" ] || continue

        found=1
        if [ "$PRUNE" -eq 1 ]; then
            if sudo rm -f "$pc"; then
                echo "[INFO] Removed dangling pkg-config metadata: $pc (missing: $missing)"
                pruned=$((pruned + 1))
            else
                echo "[WARN] Could not remove $pc (missing: $missing)"
            fi
        else
            echo "[WARN] Dangling pkg-config metadata: $pc (missing: $missing)"
        fi
    done
done

if [ "$found" -eq 0 ]; then
    exit 0
fi

if [ "$PRUNE" -eq 1 ]; then
    echo "[NOTE] Removed $pruned dangling pkg-config file(s); each owning module rewrites its metadata when it installs."
else
    echo "[NOTE] CMake will find these modules but linking will fail with 'cannot find -l<lib>'."
    echo "[NOTE] Re-run with --prune, or rebuild the stack with ./update-hyprland.sh --install."
fi

if [ "$STRICT" -eq 1 ]; then
    exit 1
fi

exit 0
