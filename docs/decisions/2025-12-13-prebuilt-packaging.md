# Prebuilt packaging choices (2025-12-13)

Context: Prebuilt Hyprland packages failed on fresh installs due to missing/incompatible deps.

Options considered:
- A) Bundle runtime deps (libhyprlang2, libdisplay-info3) as local .debs alongside Hyprland.
- B) Add pre-checks in installer: validate base libs (libstdc++6, libxkbcommon0, Qt6) meet minimum versions; on failure, fail fast with clear guidance and offer auto-fallback to source build.
- C) Produce a Trixie-targeted package set via CI/sbuild to align deps with Stable.

Chosen for this branch (deb-pkgs): Option B
- Implement version guards in `install.sh` before attempting prebuilt install.
- If requirements are not met, prompt to fallback to source build or instruct the user to upgrade (e.g. to Sid/backports) before retrying prebuilt.
- No local package builds performed in this branch.

Rationale:
- Avoids assuming the target system has Sid-level libraries.
- Keeps current prebuilt artifacts usable where the system meets requirements, while providing a safe fallback where it does not.

Next steps (tracked elsewhere):
- Evaluate Option C (CI/sbuild) to remove the runtime mismatch long-term.
