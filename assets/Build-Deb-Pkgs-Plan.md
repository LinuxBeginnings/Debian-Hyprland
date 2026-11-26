# Building, Testing and Publishing `.deb` Packages

**Status:** Proposal / not implemented
**Repository:** <https://github.com/LinuxBeginnings/Debian-Hyprland>
**Releases channel:** <https://github.com/LinuxBeginnings/Debian-Hyprland/releases>
**Related files:** `install.sh`, `update-hyprland.sh`, `dry-run-build.sh`, `hypr-tags.env`, `install-scripts/*.sh`, `debs/libinput-testing/`
**Related docs:** `README.md`, `Debian-Hyprland-Install-Upgrade.md`, `CHANGELOG.md`

---

## 1. Summary

Today every Hyprland component is compiled from source on the user's machine by
`install-scripts/<module>.sh`, installed with `cmake --install` into `/usr/local`, and
only *compiled* (never installed) by `DRY_RUN=1` / `dry-run-build.sh`. Compilation is the
fragile part: Trixie's GCC 14 / libstdc++ 14 rejects several constructs used by new
Hyprland tags (see the tag-specific patches in `install-scripts/hyprland.sh`), and the
toolchain differs between trixie, forky (testing) and sid. A user on trixie can spend
40 minutes building and end up with a hard compile error.

This proposal builds the same sources **once per Debian suite in CI**, tests the
resulting packages in a throw-away container, publishes the tested `.deb` files as
GitHub Release assets, and teaches `update-hyprland.sh` (and `install.sh`) a
`prebuilt` mode that installs those packages instead of compiling.

Design rules that drive everything below:

1. **A published `.deb` is only published after it installed and ran in a clean
   container of the target suite.** No build-only artefacts in the release channel.
2. **Prebuilt packages install to the same paths as a source build** (`/usr/local`).
   Otherwise `update-hyprland.sh`, `dry-run-build.sh` and `uninstall.sh` detection
   logic breaks, and users cannot mix modes safely.
3. **Binaries are never shared between suites.** A trixie `.deb` is never installed on
   forky or sid, and never the other way round. Suite mismatch is a hard error.
4. **Every package is traceable to a commit** of this repository plus the exact tags
   in `hypr-tags.env`.
5. **Source builds stay the default.** Prebuilt is an opt-in accelerator with an
   automatic fallback to source.

### Goals

- Remove the compile step (and its failure modes) from the common upgrade path.
- Keep trixie, forky (testing) and sid working, each with its own tested artefacts.
- Make the exact same patch set used by the installer part of the package build.
- Publish to GitHub Releases under the existing repository, with no new hosting cost.
- Let users pin a known-good build or roll back to a previous one.
- Keep the repository small: no `.deb` files committed to git.

### Non-goals

- Replacing Debian's own `hyprland` package or becoming an official Debian
  maintainer.
- Providing a fully reproducible Debian source package (`debian/` directory per
  upstream repo, `dpkg-buildpackage`, `dgit`, etc.). That is far more work for 26
  upstream projects and does not match how this repo already patches sources.
- Supporting release codenames older than trixie (bookworm is out of scope; the
  project already requires trixie/sid).
- Shipping a signing key infrastructure in phase 1 (documented, but deferred).

---

## 2. Current state (facts this plan builds on)

| Area | Today |
| --- | --- |
| Build orchestration | `update-hyprland.sh` (`DEFAULT_MODULES`), `dry-run-build.sh` (compile-only PASS/FAIL matrix), `install.sh` (interactive wizard) |
| Per-module build | `install-scripts/<module>.sh`; clones a tag into `build/src/<module>`, builds in `build/<module>`, installs with `sudo cmake --install` |
| Install prefix | `/usr/local` for almost everything; `/usr` for `hyprland-qt-support` and `hyprwayland-scanner`; `wayland-protocols-src` uses `meson --prefix=/usr/local` |
| Versions | `hypr-tags.env`; `auto`/`latest` are refreshed by `refresh-hypr-tags.sh`; `HYPRWIRE_TAG=main`, `HYPRWIRE_PROTOCOLS_TAG=hyprtavern`, `HYPRTAVERN_TAG=auto` |
| Trixie compat | `HYPR_BUILD_TRIXIE=1` exported by `update-hyprland.sh` for trixie; `hyprland.sh` carries ~20 source rewrites plus `assets/0001..0004` patches |
| Hyprland linkage | `USE_SYSTEM_HYPRLIBS=1` (the `--system` default) makes Hyprland link the separately built hyprutils/hyprlang/hyprwire instead of bundling subprojects |
| Existing shipped binaries | `assets/libglaze-dev_4.4.3-1_all.deb`, `assets/yad_0.40.0-1+b2_amd64.deb`, `debs/libinput-testing/*.deb`, `install-scripts/quickshell_0.3.0-1_amd64.deb` |
| CI | none (`.github/` contains only templates and `FUNDING.yml`) |
| Suite detection | `detect_suite` in `update-hyprland.sh`; `DEBIAN_SUITE` exported to `00-dependencies.sh` for backports/ABI handling |

Consequences for packaging:

- Because modules install into `/usr/local`, a `.deb` built by mirroring a source
  install will contain `/usr/local/bin/...`, `/usr/local/lib/libhypr*.so*`,
  `/usr/local/include/...`, `/usr/local/share/...`. Debian's own packages own
  `/usr/...`, so the two can coexist on disk. File collisions only occur for files
  Debian places under `/usr/local` (none) and for the session desktop file
  (see §5.5).
- `update-hyprland.sh` detects installed modules with paths such as
  `/usr/local/bin/hyprpaper` and `/usr/local/lib/libhyprutils.so`. Prebuilt packages
  must satisfy exactly those probes.
- `debs/libinput-testing/` proves the "ship a local `.deb` and install it with
  `dpkg -i`" pattern already used by `install.sh`
  (`ensure_libinput_min_version_from_local_debs`). Prebuilt mode reuses that helper.

---

## 3. Hard constraints and known risks

| # | Constraint / risk | Detail | Mitigation |
| --- | --- | --- | --- |
| C1 | Trixie toolchain is old | GCC 14 / libstdc++ 14 lacks `insert_range`, `append_range`, `#embed`, `string::subview`, `variant::visit`, PEP 695 in the Lua stub generator, etc. | Reuse the existing per-tag rewrites and `assets/*.patch` inside the build script; build trixie in a trixie container so `HYPR_BUILD_TRIXIE=1` is exercised |
| C2 | New tags break builds unpredictably | "Often new revisions don't compile especially on trixie" | CI builds on a schedule **and** on `hypr-tags.env` changes; a failing suite simply publishes nothing and keeps the previous release |
| C3 | ABI drift between suites | `libstdc++`, `libabsl`, `libre2`, `libdisplay-info`, `libseat` differ per suite | One build per suite, never cross-install; `Depends` derived per suite |
| C4 | SONAME changes | `libhyprutils` 0.x bumps SONAME without notice | Library package name is generated from the actual SONAME (`readelf -d`), never hardcoded |
| C5 | `/usr/local` and lintian | Debian tooling discourages `/usr/local` in packages | Accepted on purpose (rule 2); lintian runs with documented overrides. Alternative `/opt/kool` is analysed in §5.6 |
| C6 | Path collisions with Debian's `hyprland` | Both ship `share/wayland-sessions/hyprland.desktop` | Ship `hyprland-kool.desktop` instead; `Conflicts` only in the optional variant (§5.5) |
| C7 | GitHub Actions job limit | 6 h per job; a 26-module stack is 20–40 min per suite | Matrix per suite, ccache, and `--only` reuse when only app modules changed |
| C8 | `testing` is a moving target | `debian:testing` changes codename over time | Use codenames only: `trixie`, `forky`, `sid`; CI resolves `forky` explicitly |
| C9 | Mixing source and prebuilt | Users may have half the stack from source at older tags | Prebuilt mode installs the *whole* set it publishes, or runs a per-module version check and refuses on mismatch unless `--force` |
| C10 | Untrusted binaries | Release assets can be replaced | `SHA256SUMS` published with every release, verified by the consumer; optional APT signing in phase 5 |
| C11 | Large assets on Pages | GitHub Pages sites are limited to ~1 GB | Dated releases keep history; Pages/rolling tag keeps only the newest per suite |
| C12 | arm64 | Not all users are amd64; Hyprland is built natively elsewhere | amd64 first; arm64 added via `ubuntu-24.04-arm` runners + `debian:*` arm64 container images (public repos get arm64 runners) |
| C13 | Non-root assumption | Module scripts call `sudo`; `install.sh` refuses to run as root | CI creates an unprivileged `builder` user with passwordless `sudo`, exactly like a real user |

---

## 4. Architecture

```
                 hypr-tags.env (pins)  +  install-scripts/*.sh (patches, cmake flags)
                                  |
                                  v
+-----------------------------------------------------------------------+
|  packaging/build-debs.sh        (runs inside debian:<suite> container) |
|                                                                       |
|  for module in build order:                                            |
|    1. run install-scripts/<module>.sh   with the orchestrator env      |
|    2. stage: DESTDIR=/work/stage/<pkg> cmake --install <build>         |
|       (plus explicit copies for scripts that use sudo install -d)      |
|    3. compute file list, strip build junk, dpkg-shlibdeps -> Depends   |
|    4. dpkg-deb --build --root-owner-group  -> out/<suite>/*.deb        |
|    5. dpkg -i the new debs into the same container                     |
|       (so the next module builds against real packaged libs)           |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
|  packaging/tests/run-install-test.sh  (fresh container per suite)      |
|  - apt-get install -y ./out/<suite>/*.deb  (dependency resolution)     |
|  - Hyprland --version, ldd sweep, hyprctl --version, desktop entry     |
|  - upgrade to the same version, then purge, then reinstall             |
|  - any failure => suite is UNTESTED and cannot be published            |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
|  publish: GitHub Releases on LinuxBeginnings/Debian-Hyprland           |
|  tag debs-<suite>-<date> (immutable)  +  debs-<suite> (rolling)        |
|  assets: *.deb, Packages.gz, Release, SHA256SUMS, build-info.json      |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
|  consumer: ./update-hyprland.sh --mode prebuilt                        |
|  detect suite+arch -> fetch Packages.gz -> compare with hypr-tags.env  |
|  -> apt install local debs -> verify -> fallback to source on failure  |
+-----------------------------------------------------------------------+
```

Two publish channels are possible (see §10): Releases only (simplest) or a real APT
repository on `gh-pages` (nicest for users). Layout A is the recommended starting
point; Layout B is the same pipeline plus one extra publish step.

---

## 5. Package model

### 5.1 Naming

All packages carry a `-kool` suffix so they never shadow, `Provides:` or `Conflicts:`
with Debian's `hyprland` stack by accident. The prefix also makes
`apt purge '*-kool'` a one-liner rollback.

| Module (`install-scripts/`) | Upstream | Proposed binary package(s) | Install prefix |
| --- | --- | --- | --- |
| `xkbcommon` | xkbcommon/libxkbcommon | `libxkbcommon-kool0`, `libxkbcommon-kool-dev`, `xkbcommon-kool-tools` (already present on Debian; only build if pinned tag > distro) | verify in script (meson) |
| `hyprutils` | hyprwm/hyprutils | `libhyprutils-kool<SONAME>` (+ `-dev`) | `/usr/local` |
| `hyprlang` | hyprwm/hyprlang | `libhyprlang-kool<SONAME>` (+ `-dev`) | `/usr/local` |
| `hyprcursor` | hyprwm/hyprcursor | `libhyprcursor-kool<SONAME>` (+ `-dev`) | `/usr/local` |
| `aquamarine` | hyprwm/aquamarine | `libaquamarine-kool<SONAME>` (+ `-dev`) | `/usr/local` |
| `hyprgraphics` | hyprwm/hyprgraphics | `libhyprgraphics-kool<SONAME>` (+ `-dev`) | `/usr/local` |
| `hyprtoolkit` | hyprwm/hyprtoolkit | `hyprtoolkit-kool` (lib + dev, single package) | `/usr/local` |
| `hyprwayland-scanner` | hyprwm/hyprwayland-scanner | `hyprwayland-scanner-kool` | `/usr` |
| `wayland-protocols-src` | wayland-protocols | `wayland-protocols-kool` | `/usr/local` |
| `hyprland-protocols` | hyprwm/hyprland-protocols | `hyprland-protocols-kool` | `/usr/local` |
| `hyprland-qt-support` | hyprwm/hyprland-qt-support | `hyprland-qt-support-kool` | `/usr` |
| `hyprland-guiutils` | hyprwm/hyprland-guiutils | `hyprland-guiutils-kool` | `/usr/local` |
| `hyprwire` | hyprwm/hyprwire | `libhyprwire-kool<SONAME>` (+ `-dev`) | `/usr/local` |
| `hyprwire-protocols` | hyprwm/hyprwire-protocols | `hyprwire-protocols-kool` | `/usr/local/share/hyprwire-protocols` |
| `hyprland` | hyprwm/Hyprland | `hyprland-kool` (compositor, `hyprctl`, `hyprpm`, `start-hyprland`, session file) | `/usr/local` |
| `hypridle` | hyprwm/hypridle | `hypridle-kool` | CMake default (`/usr/local`) |
| `hyprlock` | hyprwm/hyprlock | `hyprlock-kool` | CMake default (`/usr/local`) |
| `hyprpaper` | hyprwm/hyprpaper | `hyprpaper-kool` | `/usr/local` |
| `hyprpicker` | hyprwm/hyprpicker | `hyprpicker-kool` | CMake default (`/usr/local`) |
| `hyprpolkitagent` | hyprwm/hyprpolkitagent | `hyprpolkitagent-kool` | `/usr/local` |
| `hyprshutdown` | hyprwm/hyprshutdown | `hyprshutdown-kool` | CMake default (`/usr/local`) |
| `hyprpwcenter` | hyprwm/hyprpwcenter | `hyprpwcenter-kool` | CMake default (`/usr/local`) |
| `hyprtavern` | hyprwm/hyprtavern | `hyprtavern-kool` | CMake default (`/usr/local`) |
| `hyprsunset` | hyprwm/hyprsunset | `hyprsunset-kool` | CMake default (`/usr/local`) |
| `hyprlauncher` | hyprwm/hyprlauncher | `hyprlauncher-kool` | CMake default (`/usr/local`) |
| `hyprsysteminfo` | hyprwm/hyprsysteminfo | `hyprsysteminfo-kool` | CMake default (`/usr/local`) |
| (meta) | — | `hyprland-kool-full` (Depends on everything above) | — |
| (build) | — | `hyprland-kool-build-deps` (metapackage, §6.3) | — |

`<SONAME>` must be read at build time:

```bash
soname=$(readelf -d /usr/local/lib/libhyprutils.so.5 | sed -n 's/.*SONAME.*\[\(.*\)\]/\1/p')
# libhyprutils.so.5 -> package libhyprutils-kool5
```

Do **not** hardcode `1`, `2`, `5`. Upstream bumps majors during a release cycle, and
a wrong major produces a package that cannot satisfy `dpkg-shlibdeps` output.

### 5.2 Version scheme

| Tag value in `hypr-tags.env` | Package version |
| --- | --- |
| `v0.57.2` | `0.57.2-1+trixie1` |
| `v0.9.7` (app) | `0.9.7-1+trixie1` |
| `main`, `auto`, `hyprtavern` | `0.0.0~git20261125.<sha7>-1+trixie1` |
| `1.50` (`WAYLAND_PROTOCOLS_TAG`) | `1.50-1+trixie1` |

- The `+<suite><serial>` suffix keeps the suite visible in `dpkg -l` and guarantees
  strict ordering (`-2+trixie1` > `-1+trixie1`).
- If the scheme ever has to change retroactively, add `Epoch: 1` in the control file
  at that point. No epoch now.
- The package name must stay the same across suites so `apt` upgrades a package in
  place; the *suite tag* on the repository separates them, not the name.
- `hypr-tags.env` is the source of truth. `build-info.json` (published with the
  release) records the full `hypr-tags.env` plus the repository commit, so a build
  can always be reproduced: `git checkout <commit> && ./packaging/build-debs.sh --suite trixie`.

### 5.3 Split vs. fat packaging

Three options were considered:

| Option | Pros | Cons | Verdict |
| --- | --- | --- | --- |
| **Split** (one package per module, libs separate) | Fine-grained upgrades, real dependency graph, `ldd` validation meaningful, matches source build | ~30 control files, more test permutations | **Recommended** |
| **Fat** (`hyprland-kool-full` only) | One file per suite, trivial publish | 250 MB+ per download for a one-line app fix; a single broken app module blocks the compositor | Keep as meta-package only |
| Hybrid (core + apps) | Fewer packages | Two-level dependency resolution hides which lib is stale | Acceptable fallback if control-file maintenance becomes a burden |

Because `hyprland.sh` is already built against system hyprlibs
(`USE_SYSTEM_HYPRLIBS=1`), splitting is natural: each `.so` already lives in its own
module's install tree. The one hard requirement is that the build script installs
each module's `.deb` into the build container **before** building the next module, so
that downstream modules really link the packaged libraries (this doubles as an
install test, see C9).

### 5.4 Anatomy of a generated package

`dpkg-deb --build` on a staged tree, with a generated control file. Example
`hyprpaper-kool`:

```
stage/hyprpaper-kool/
├── DEBIAN/
│   ├── control
│   ├── md5sums                 (dpkg-deb can generate; prefer explicit)
│   └── postinst                (ldconfig; optional)
└── usr/
    └── local/
        ├── bin/hyprpaper
        └── share/man/man1/hyprpaper.1.gz
```

`control`:

```
Package: hyprpaper-kool
Source: hyprpaper-kool
Version: 0.8.5-1+trixie1
Architecture: amd64
Maintainer: LinuxBeginnings <maintainer-address-from-CONTRIBUTING>
Installed-Size: 412
Section: x11
Priority: optional
Depends: libc6 (>= 2.38), libstdc++6 (>= 13), libwayland-client0, libwayland-egl1,
 libhyprutils-kool5 (>= 0.14.4), libhyprlang-kool2 (>= 0.6.8),
 libhyprgraphics-kool4 (>= 0.5.0), libmagic1 | libmagic1t64
Description: KooL Hyprpaper build (upstream v0.8.5, source-patched)
 Hyprpaper wallpaper daemon built from upstream tag v0.8.5 by the
 Debian-Hyprland installer, with the same source patches the installer applies.
 Installs into /usr/local, matching a source install of this repository.
Homepage: https://github.com/LinuxBeginnings/Debian-Hyprland
Built-Using: hypr-tags.env@<repo-commit>
```

Notes:

- `Depends` is **generated**, never written by hand:
  `dpkg-shlibdeps --ignore-missing-info -l/usr/local/lib -e<staged-binary>` produces
  the library list; the build script then rewrites `/usr/local`-owned library names
  to the matching `-kool` packages via the `shlibs` file it generates per package:
  ```
  # stage/libhyprutils-kool5/DEBIAN/shlibs
  libhyprutils 5 libhyprutils-kool5 (>= 0.14.4)
  ```
  With per-package `DEBIAN/shlibs`, `dpkg-shlibdeps` resolves intra-repo dependencies
  correctly and `--ignore-missing-info` is only needed for libraries that are not in
  the local shlibs database (e.g. Debian's older copies).
- Multi-arch path (`/usr/local/lib/x86_64-linux-gnu`) must be added with `-l` too.
- `Maintainer:` must be a real address: reuse whatever `CONTRIBUTING.md` /
  `COMMIT_MESSAGE_GUIDELINES.md` prescribes; do not invent one in the build script.
- `Installed-Size` is computed with `du -k -s` on the staged tree.
- `Built-Using` is not valid for binary-only packages in Debian policy terms, but it
  is harmless metadata; alternatively record the commit in `build-info.json` only.

### 5.5 Conflicts, session file, and Debian coexistence

| Path | Debian `hyprland` | `hyprland-kool` |
| --- | --- | --- |
| `/usr/bin/Hyprland` | yes | no |
| `/usr/local/bin/Hyprland` | no | yes |
| `/usr/share/wayland-sessions/hyprland.desktop` | yes | **no** |
| `/usr/local/share/wayland-sessions/hyprland-kool.desktop` | no | yes |

- Shipping `hyprland-kool.desktop` avoids the only real file collision and lets a
  display manager show both sessions, so users can A/B test.
- The desktop `Exec` must point at the absolute path
  `/usr/local/bin/start-hyprland` (or `/usr/local/bin/Hyprland` when the tag has no
  wrapper) so it does not depend on `PATH` ordering in the DM environment.
- Default policy: **no `Conflicts:`**, co-installable. `install.sh` already purges
  Debian `hypr*` packages before source builds; prebuilt mode keeps that behaviour
  by default (`--keep-debian-hypr` opts out) so `/usr/bin/hyprctl` cannot shadow the
  packaged one for users who have both.
- A `hyprland-kool-strict` variant may later add
  `Conflicts: hyprland, hyprland-backgrounds` plus `Provides: hyprland` for users who
  want apt to treat it as *the* Hyprland.

### 5.6 Install prefix decision (`/usr/local` vs `/opt/kool`)

| | `/usr/local` (recommended) | `/opt/kool` |
| --- | --- | --- |
| Matches current source install | yes | no |
| `update-hyprland.sh` probes keep working unchanged | yes | no (needs dual probes) |
| Mixing source and prebuilt | safe | unsafe |
| lintian | flags `/usr/local` paths; needs overrides | clean |
| Needs `ld.so.conf.d` | usually already includes `/usr/local/lib` | must ship a drop-in |
| Needs `PATH` changes | `/usr/local/bin` already first | must ship `/etc/profile.d` + DM env |

Decision: **`/usr/local`**, with lintian overrides checked into
`packaging/lintian/hyprland-kool.lintian-overrides`. The whole point is
interchangeability with source installs; a "cleaner" prefix would create a second,
divergent installation mode.

Caveat for `hyprland-qt-support` and `hyprwayland-scanner`, which currently install
to `/usr`: the package build normalises them to `/usr/local`
(`-DCMAKE_INSTALL_PREFIX=/usr/local`), and a follow-up should change the two module
scripts to do the same so source and prebuilt agree. Until then, prebuilt mode must
not overwrite `/usr` files and must note the difference in the release body.

---

## 6. Debian dependencies

Everything below is required. Two rules:

- **Build dependencies** are installed by `install-scripts/00-dependencies.sh`
  verbatim; the package build must not carry a second, drifting list.
- **Runtime dependencies** are generated by `dpkg-shlibdeps`. The tables in §6.2 are
  the expected result and are used for review and for the CI `dpkg -I` assertion —
  they are not the source of truth.

### 6.1 Build-time dependencies (host / container)

From `install-scripts/00-dependencies.sh` (`dependencies[]`):

```
build-essential cmake cmake-extras clang ddcutil llvm pkgconf curl findutils
gawk gettext gir1.2-graphene-1.0 git glslang-tools gobject-introspection golang
hwdata jq libavcodec-dev libavformat-dev libavutil-dev libcairo2-dev libdeflate-dev
libdrm-dev libegl-dev libegl1-mesa-dev libgbm-dev libgdk-pixbuf-2.0-dev
libgdk-pixbuf2.0-bin libgirepository1.0-dev libgl-dev libglvnd-dev libglx-dev
libgraphene-1.0-0 libgraphene-1.0-dev libgtk-3-dev libgulkan-0.15-0t64 libgulkan-dev
libinih-dev libiniparser-dev libinput-dev libjbig-dev libjpeg-dev libjpeg62-turbo-dev
liblerc-dev libliftoff-dev liblzma-dev libnotify-bin libopengl-dev mesa-common-dev
libpam0g-dev libpango1.0-dev libpipewire-0.3-dev libqt6svg6 libsdbus-c++-dev
libseat-dev libstartup-notification0-dev libswresample-dev libsystemd-dev libtiff-dev
libtiffxx6 libtomlplusplus-dev libudev-dev libvkfft-dev libvulkan-dev
libvulkan-volk-dev libwayland-dev libwayland-bin libwebp-dev libxcb-composite0-dev
libxcb-cursor-dev libxcb-dri3-dev libxcb-ewmh-dev libxcb-icccm4-dev
libxcb-present-dev libxcb-render-util0-dev libxcb-res0-dev libxcb-util-dev
libxcb-xinerama0-dev libxcb-xinput-dev libxcb-xkb-dev libxkbcommon-dev
libxkbcommon-x11-dev libxkbregistry-dev libxml2-dev libxxhash-dev meson
network-manager ninja-build openssl psmisc python3-mako python3-markdown
python3-markupsafe python3-pyquery python3-yaml qalculate-gtk qt6-base-dev rsync
scdoc seatd socat spirv-tools unzip util-linux vulkan-utility-libraries-dev
vulkan-validationlayers xdg-desktop-portal xwayland
```

From `hyprland_dep[]` (Hyprland itself):

```
bc lnav binutils libc6 libcairo2-dev libcanberra-dev libdrm2 libeis-dev libjpeg-dev
libjxl-dev libmagic-dev libmuparser-dev libpixman-1-dev libpugixml-dev libre2-dev
librsvg2-dev libspng-dev libtomlplusplus-dev libwebp-dev libzip-dev libpam0g-dev
libxcursor-dev libxcb-errors-dev libudis86-dev libinotify-ocaml-dev
qt6-declarative-dev qt6-base-private-dev qt6-wayland-dev qt6-wayland-private-dev
```

Plus, per module (`install-scripts/<module>.sh` dependency arrays):

| Module | Declared build dependencies |
| --- | --- |
| `xkbcommon` | `bison libzip-dev librsvg2-dev` (+ meson/ninja from the main list) |
| `hyprcursor` | `libzip-dev librsvg2-dev` |
| `hyprgraphics` | `libmagic-dev libjpeg-dev libwebp-dev` |
| `hyprwayland-scanner` | `libpugixml-dev libwayland-dev libwayland-bin libexpat1-dev libffi-dev` |
| `hyprland-protocols` | `cmake pkgconf git` |
| `hyprland-qt-support` | `qt6-base-dev qt6-wayland qt6-declarative-dev qml6-module-qtcore qml6-module-qtquick-layouts qt6-tools-dev qt6-tools-dev-tools qt6-charts-dev` |
| `hyprland-guiutils` | `libqt6core5compat6 qt6-base-dev qt6-wayland-dev qt6-wayland qt6-declarative-dev qml6-module-qtcore qt6-3d-dev qt6-5compat-dev libqt6waylandclient6 qml6-module-qtwayland-client-texturesharing` |
| `hypridle` | `libsdbus-c++-dev` |
| `hyprlock` | `libpam0g-dev libgbm-dev libdrm-dev libmagic-dev libaudit-dev libsdbus-c++-dev` (+ `build_dep: pam`) |
| `hyprpaper` | `cmake ninja-build pkg-config build-essential libwayland-dev libxkbcommon-dev libpixman-1-dev libdrm-dev libmagic-dev` |
| `hyprpolkitagent` | `libsdbus-c++-dev libdrm-dev libpixman-1-dev libpolkit-agent-1-dev libpolkit-qt6-1-dev mate-polkit` |
| `hyprlauncher` | `libqalculate-dev` |
| `hyprsysteminfo` | `libpci-dev` (+ Qt6 QML modules from `preflight_checks`) |
| `hyprtoolkit` | none declared — links hyprutils/hyprgraphics/hyprlang + `libsdbus-c++` |

Qt6 QML modules additionally required by `preflight_checks()`:

```
qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-templates
qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtquick-shapes
qml6-module-qt-labs-qmlmodels
```

Suite-specific build adjustments already handled by the scripts (the package build
inherits them by calling the same scripts):

- `DEBIAN_SUITE=trixie`: `libxkbcommon-dev`, `libxkbcommon-x11-dev`,
  `libxkbregistry-dev`, `libgtk-3-dev`, `qt6-base-private-dev` come from
  `trixie-backports`; clang 21 is installed from `apt.llvm.org` when available.
- `libre2`/`libabsl` ABI consistency check (`ensure_re2_absl_consistent`) must stay.
- `libdisplay-info`: `libdisplay-info2` on trixie, `libdisplay-info3` on forky/sid.
- Glaze ≥ 4.4: `assets/libglaze-dev_4.4.3-1_all.deb` is installed when
  `/usr/include/glaze` is missing.

**Packaging build deps (the tooling itself)**, not covered above:

```
dpkg-dev debhelper fakeroot lintian apt-utils xz-utils zstd file readelf-binutils
gpg ca-certificates curl jq rsync shellcheck
```

(`debhelper` is only needed if `dh` is ever used; `dpkg-deb` alone does not need it.)

### 6.2 Runtime dependencies per package (expected `dpkg-shlibdeps` output)

Common baseline (all binaries):

```
libc6 (>= 2.38), libstdc++6 (>= 13), libgcc-s1
```

Library / compositor packages:

| Package | Expected runtime dependencies (indicative) |
| --- | --- |
| `libhyprutils-kool<SONAME>` | `libc6 libstdc++6 libpixman-1-0 libwayland-client0 libwayland-server0 libxkbcommon0` (optional: `libdrm2` when built with DRM helpers) |
| `libhyprlang-kool<SONAME>` | `libc6 libstdc++6` |
| `libhyprcursor-kool<SONAME>` | `libc6 libstdc++6 libzip5 (libzip4 on trixie), librsvg2-2 libmagic1` |
| `libaquamarine-kool<SONAME>` | `libc6 libstdc++6 libdrm2 libgbm1 libegl1 libgl1 libopengl0 libwayland-client0 libwayland-server0 libwayland-egl1 libxkbcommon0 libinput10 libseat1 libudev1 libdisplay-info2` (trixie) / `libdisplay-info3` (forky, sid), `libpixman-1-0`, `libhwdata`/`hwdata` |
| `libhyprgraphics-kool<SONAME>` | `libc6 libstdc++6 libcairo2 libjpeg62-turbo libwebp7 libmagic1 libjxl0.7` (trixie) / `libjxl0.11` (forky, sid), `librsvg2-2 libspng0 libdeflate0 libpixman-1-0` |
| `hyprtoolkit-kool` | `libc6 libstdc++6 libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libxkbcommon0 libwayland-client0 libsdbus-c++2 libhyprutils-kool* libhyprgraphics-kool* libhyprlang-kool*` |
| `hyprwayland-scanner-kool` | `libc6 libstdc++6 libpugixml1v5 libexpat1` |
| `hyprland-protocols-kool` | none (data only) |
| `hyprland-qt-support-kool` | `libc6 libstdc++6 libqt6core6t64 libqt6gui6t64 libqt6qml6 libqt6quick6 libqt6waylandclient6` |
| `hyprland-guiutils-kool` | Qt6 runtime set + `libqt6core5compat6` + hypr libs |
| `libhyprwire-kool<SONAME>` | `libc6 libstdc++6 libwayland-client0` (+ hyprutils) |
| `hyprwire-protocols-kool` | none (XML data + `.pc`) |
| `wayland-protocols-kool` | none (`.pc` + XML data) |
| `hyprland-kool` | `libc6 (>= 2.38) libstdc++6 (>= 13) libwayland-client0 libwayland-server0 libwayland-egl1 libdrm2 libgbm1 libegl1 libgl1 libopengl0 libxkbcommon0 libxkbregistry0 libpixman-1-0 libinput10 libseat1 libudev1 libsystemd0 libpam0g libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libjpeg62-turbo libwebp7 libmagic1 libmuparser2v5 libre2-11 librsvg2-2 libspng0 libzip5 libtomlplusplus3 libcanberra0 libeis1 libxcb1 libxcb-icccm4 libxcb-ewmh2 libxcb-xinput0 libxcb-composite0 libxcb-dri3-0 libxcb-present0 libxcb-render-util0 libxcb-res0 libxcb-util1 libxcb-xinerama0 libxcb-xkb1 libxcursor1 libxcb-errors0 libudis86-0 libjxl0.7 libdeflate0 libpugixml1v5 libdisplay-info2 libliftoff0 libhyprutils-kool* libhyprlang-kool* libhyprcursor-kool* libaquamarine-kool* libhyprgraphics-kool* libhyprwire-kool*` |
| `hypridle-kool` | `libc6 libstdc++6 libsdbus-c++2 libwayland-client0 libhyprlang-kool* libhyprutils-kool*` |
| `hyprlock-kool` | `libc6 libstdc++6 libpam0g libgbm1 libdrm2 libmagic1 libaudit1 libsdbus-c++2 libwayland-client0 libxkbcommon0 libcairo2 libpango-1.0-0 libhyprgraphics-kool* libhyprlang-kool* libhyprutils-kool*` |
| `hyprpaper-kool` | `libc6 libstdc++6 libwayland-client0 libmagic1 libhyprgraphics-kool* libhyprlang-kool* libhyprutils-kool*` |
| `hyprpicker-kool` | `libc6 libstdc++6 libwayland-client0 libxkbcommon0 libcairo2 libhyprutils-kool*` |
| `hyprpolkitagent-kool` | `libc6 libstdc++6 libpolkit-agent-1-0 libpolkit-qt6-1-1 libsdbus-c++2 libqt6core6t64 libqt6qml6 libqt6quick6` |
| `hyprshutdown-kool` | `libc6 libstdc++6 libwayland-client0 libhyprlang-kool* libhyprutils-kool*` |
| `hyprpwcenter-kool` | `libc6 libstdc++6` + hypr libs + Qt6 if built with Qt |
| `hyprtavern-kool` | `libc6 libstdc++6 libsdbus-c++2 libhyprwire-kool* libhyprutils-kool*` |
| `hyprsunset-kool` | `libc6 libstdc++6 libwayland-client0 libhyprlang-kool* libhyprutils-kool*` |
| `hyprlauncher-kool` | `libc6 libstdc++6 libqalculate22t64 libwayland-client0` + hypr libs |
| `hyprsysteminfo-kool` | `libc6 libstdc++6 libpci3 libqt6core6t64 libqt6gui6t64 libqt6qml6 libqt6quick6 libqt6svg6 libqt6waylandclient6` |

**These names change between suites.** Verified examples on a forky/sid system:
`libmagic1` → `libmagic1t64`, `libzip4` → `libzip5`, `libdisplay-info2` →
`libdisplay-info3`, `libwebp7` → `libwebp12`, `libjxl0.7` → `libjxl0.11`. This is
exactly why `Depends` must be computed inside the target container by
`dpkg-shlibdeps`, and why any hand-written list in a `control.in` template must only
contain the `-kool` intra-repo names plus an alternative fallback where a rename is
known (`libmagic1 | libmagic1t64`).

Additional non-library runtime requirements that `dpkg-shlibdeps` cannot see:

| Package | Also needs |
| --- | --- |
| `hyprland-kool` | `hwdata` (PCI/USB ids), `xdg-desktop-portal` + `xdg-desktop-portal-hyprland` (installed separately by the repo), `xwayland` (X11 apps), `seatd` or systemd-logind, `polkit` for the agent |
| `hyprpolkitagent-kool` | `polkitd` (or `polkit`), one authentication agent UI (`mate-polkit`, `polkit-kde-agent-1`, or `lxpolkit`) |
| `hyprlauncher-kool` | `qalculate-gtk` only if the dots bind it; the library `libqalculate22t64` is enough for the binary |
| `hyprsysteminfo-kool` | `pciutils`/`libpci3` for `lspci` data |
| `hyprpaper-kool` | `libmagic1` for MIME sniffing of wallpapers |
| all Qt6 GUI apps | `qt6-wayland`, `qt6-qpa-plugins`, plus the QML modules listed in §6.1 |
| `hyprland-kool` (session) | `libinput10` version ≥ 1.29 — re-use `ensure_libinput_min_version_from_local_debs` and `debs/libinput-testing/` when the suite is older |

### 6.3 `hyprland-kool-build-deps` metapackage

A tiny `Architecture: all` package whose `Depends` is the union of §6.1. Its purpose:
one `apt install hyprland-kool-build-deps` reproduces the build environment, and CI
can diff its `Depends` against `00-dependencies.sh` to catch drift. It is *not*
published to end users in the default channel (or published under `devel/` only).

### 6.4 CI / test-only dependencies

```
docker.io (or the runner's docker), debootstrap, lintian, piuparts, apt-utils,
dpkg-dev, xz-utils, zstd, gnupg, ca-certificates, curl, jq, coreutils, file
```

`piuparts` is optional but valuable: it installs, upgrades, removes and purges the
package in a chroot and reports leftover files.

---

## 7. Build pipeline design

### 7.1 Repository layout (Layout A, recommended)

```
Debian-Hyprland/
├── .github/
│   └── workflows/
│       ├── build-debs.yml          # matrix build + test, uploads artifacts
│       └── publish-debs.yml        # release publish from artifacts (tag push/manual)
├── packaging/
│   ├── README.md                   # how to run locally, how to add a module
│   ├── build-debs.sh               # entry point: --suite S --arch A [--only LIST]
│   ├── publish-debs.sh             # gh release create/upload + Packages.gz + SHA256SUMS
│   ├── publish-apt.sh              # optional: dists/ tree for gh-pages (Layout B)
│   ├── lib/
│   │   ├── deb-common.sh           # logging, suite detect, version math
│   │   ├── deb-stage.sh            # DESTDIR staging + manifest diffing
│   │   ├── deb-control.sh          # control/shlibs/postinst generation
│   │   └── deb-manifest.sh         # module -> package mapping (single source of truth)
│   ├── manifests/
│   │   ├── hyprland-kool.files     # expected file globs (assertion, not selection)
│   │   ├── libhyprutils-kool.files
│   │   └── ...
│   ├── control/
│   │   ├── hyprpaper-kool.control.in
│   │   └── ...
│   ├── scripts/
│   │   ├── postinst-ldconfig.sh
│   │   ├── postrm-ldconfig.sh
│   │   └── preinst-check.sh
│   ├── tests/
│   │   ├── run-install-test.sh     # fresh container install/upgrade/purge
│   │   ├── run-ldd-sweep.sh
│   │   └── suites.sh
│   ├── lintian/
│   │   └── hyprland-kool.lintian-overrides
│   └── out/                        # gitignored; .deb + Packages.gz land here
├── debs/                           # existing vendored debs, unchanged
│   └── libinput-testing/
├── hypr-tags.env
├── install.sh
├── update-hyprland.sh
└── dry-run-build.sh
```

`.gitignore` additions:

```
packaging/out/
packaging/stage/
packaging/work/
```

### 7.2 `packaging/build-debs.sh` contract

```
Usage: ./packaging/build-debs.sh --suite <trixie|forky|sid> [options]
  --suite S            target suite (mandatory)
  --arch A             amd64 (default) | arm64
  --only LIST          comma-separated modules (default: packaging/lib/deb-manifest.sh order)
  --skip LIST          comma-separated modules
  --jobs N             parallel compile jobs (default: nproc)
  --out DIR            output dir (default: packaging/out/<suite>/<arch>)
  --no-install-test    build only (debugging; CI always tests)
  --keep-stage         keep staging trees for inspection
  --ref REF            build a specific repo ref (CI uses the checked-out SHA)
```

Steps per module:

1. **Environment parity.** Export exactly what `update-hyprland.sh::run_stack`
   exports, so a package is the same build a user would get:
   `HYPR*_TAG`, `WAYLAND_PROTOCOLS_TAG`, `HYPR_BUILD_TRIXIE`,
   `USE_SYSTEM_HYPRLIBS=1`, `DEBIAN_SUITE`, `PATH=/usr/local/bin:$PATH`,
   `PKG_CONFIG_PATH`, `CMAKE_PREFIX_PATH=/usr/local`.
   *Assert* `USE_SYSTEM_HYPRLIBS=1` — a bundled Hyprland cannot be split into
   packages (C4).
2. **Build.** Run `install-scripts/<module>.sh` with `DRY_RUN` unset. Do **not**
   reimplement clone/cmake logic; the script owns the patches. Capture
   `Install-Logs/*.log` into the artifact bundle.
3. **Stage.** Re-run the install step into a private root instead of `/usr/local`:
   `DESTDIR="$STAGE" cmake --install "$BUILD_ROOT/<module>"`. For modules that use
   `sudo install -d`/`cp`/`meson install` (see table in §7.3), the script either
   respects `DESTDIR` (cmake, meson) or needs an explicit copy step driven by the
   module's manifest. Anything that cannot be staged must be listed in
   `packaging/manifests/<pkg>.files` and copied explicitly.
4. **Sanitise.** Remove `*.la`, `cmake` install manifests, empty dirs, and
   `INSTALL`/`LICENSE` duplicates; strip binaries (`strip --strip-unneeded` on
   `.so*` and executables, keep debug info out unless `--debug`).
5. **Control.** Generate `DEBIAN/control`, `DEBIAN/shlibs` (libs only),
   `DEBIAN/md5sums`, `postinst`/`postrm` where needed. Version comes from
   `hypr-tags.env` + suite (§5.2).
6. **Build.** `dpkg-deb --build --root-owner-group -Zxz "$STAGE" "$OUT/<pkg>_<ver>_<arch>.deb"`,
   with `SOURCE_DATE_EPOCH` set to the tagged commit time for reproducibility.
7. **Install into the build container.** `dpkg -i` the new debs (or
   `apt-get install -y ./...`), then `ldconfig`. This proves the package is
   installable *and* lets the next module link real packaged libraries.
8. **Assert.** Diff `dpkg-deb -c` against `manifests/<pkg>.files`; fail on unexpected
   paths outside the allow-list (`/usr/local/**`, `/usr/share/wayland-sessions/hyprland-kool.desktop`,
   `/usr/lib/systemd/user/*-kool.service`).

### 7.3 Per-module staging recipe

| Module | Install mechanism | Staging note |
| --- | --- | --- |
| `hyprutils`, `hyprlang`, `hyprcursor`, `aquamarine`, `hyprgraphics`, `hyprtoolkit`, `hyprland-protocols`, `hyprland-guiutils`, `hyprwire`, `hyprland`, `hyprpaper`, `hyprpolkitagent` | `sudo cmake --install "$BUILD_DIR"` | `DESTDIR` works; `sudo` is a no-op shim in CI |
| `hypridle`, `hyprlock`, `hyprpicker`, `hyprsunset`, `hyprlauncher`, `hyprshutdown`, `hyprpwcenter`, `hyprtavern`, `hyprsysteminfo` | `cmake --install` with default prefix | same as above; verify prefix is `/usr/local` in the file list |
| `hyprland-qt-support` | `cmake --install` with `-DCMAKE_INSTALL_PREFIX=/usr` | override to `/usr/local` for packaging (§5.6) |
| `hyprwayland-scanner` | `cmake -DCMAKE_INSTALL_PREFIX=/usr` | override to `/usr/local` |
| `wayland-protocols-src` | `meson install --prefix=/usr/local` | `DESTDIR` works (`meson install --destdir`) |
| `hyprwire-protocols` | `install -d` + `cp -r` + generated `.pc` | no cmake; copy from `$SRC_ROOT/hyprwire-protocols` and regenerate the `.pc` with the package version |
| `xkbcommon` | meson/ninja (see script) | build only when `XKB*` pin > distro version; otherwise declare `Depends: libxkbcommon0 (>= ...)` and skip the package |
| `hyprland` (session file) | `cmake --install` writes `share/wayland-sessions/hyprland.desktop` | rename to `hyprland-kool.desktop` in the staging tree and rewrite `Exec=` |

### 7.4 Reproducibility

- `SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)` for `dpkg-deb`.
- Fixed build user/group via `--root-owner-group`.
- Deterministic file ordering (`find | LC_ALL=C sort`).
- Same container image digest per suite, recorded in `build-info.json`
  (`image: debian:trixie@sha256:...`).
- Two builds of the same commit+suite should produce identical `.deb` hashes; CI can
  assert this weekly (nice-to-have, not a gate).

---

## 8. Test gate (this is the part that makes publishing safe)

A suite is publishable only if **all** steps below pass. Any failure keeps the
previous release in place.

### Stage 1 — Static checks (same container as the build)

```bash
dpkg-deb --info  out/*.deb
dpkg-deb --contents out/*.deb
lintian --fail-on error,warning --suppress-tags-from-file packaging/lintian/*.overrides out/*.deb
# every ELF has a resolved interpreter and no unresolved NEEDED
for deb in out/*.deb; do dpkg-deb -x "$deb" /tmp/x; done
```

Assertions:

- `Package`, `Version`, `Architecture` correct and suite suffix present.
- No file outside the allow-list (§7.2 step 8).
- `Depends` contains every `-kool` library the binaries actually need.
- No absolute RPATH pointing into `build/` (`readelf -d | grep -i path`).
- `Installed-Size` fields present.

### Stage 2 — Clean-container install (the real gate)

```bash
docker run --rm -v "$PWD/packaging/out/trixie:/debs:ro" debian:trixie bash -c '
  apt-get update
  apt-get install -y --no-install-recommends /debs/*.deb   # apt resolves Depends
  ldconfig
  Hyprland --version
  hyprctl --version
  ldd /usr/local/bin/Hyprland | grep -q "not found" && exit 1
  for f in /usr/local/bin/* /usr/local/lib/*.so*; do ldd "$f" 2>/dev/null | grep "not found" && exit 1; done
  test -f /usr/local/share/wayland-sessions/hyprland-kool.desktop
  desktop-file-validate /usr/local/share/wayland-sessions/hyprland-kool.desktop
'
```

`apt-get install ./file.deb` (not `dpkg -i`) is deliberate: it proves `Depends` is
complete on a *bare* suite image. A missing dependency must fail the gate, not be
papered over.

Additional checks:

- `dpkg -l | grep -c '^ii.*-kool'` equals the expected package count.
- `apt-get -s remove '*-kool'` shows no package from the base system would be removed.
- Extract all `.pc`/`cmake` files and verify `pkg-config --modversion hyprutils`
  resolves to the packaged version (catches a stale `/usr/local` overlay).
- If the pinned tag is newer than the suite's own `hyprland`, assert the distro
  package is not pulled in (`apt-cache policy hyprland` unchanged).

### Stage 3 — Upgrade / downgrade / purge

```bash
# upgrade: install previous release, then this one
apt-get install -y /debs-previous/*.deb && apt-get install -y /debs/*.deb
dpkg -l '*-kool'            # all at the new version, none half-installed

# downgrade must also work (users pin builds)
apt-get install -y --allow-downgrades /debs-previous/*.deb

# purge leaves nothing behind
apt-get purge -y '*-kool' && apt-get autoremove -y
test -z "$(dpkg -l | grep -- '-kool')"
test ! -e /usr/local/bin/Hyprland
test ! -e /usr/local/share/wayland-sessions/hyprland-kool.desktop
```

### Stage 4 — Runtime smoke test (best effort)

Inside the same container, on a headless/software path if the pinned tag supports it:

- `Hyprland --version` (always)
- `hyprctl version` against a running instance **only if** a headless backend works
  for that tag — verify at implementation time (`AQ_HEADLESS`/`WLR_BACKENDS` behaviour
  is upstream-version-specific; do not assume it).
- Parse a minimal config: `Hyprland --config /dev/null`-style flags vary by version;
  treat "config parses" as optional.

If the runtime smoke test cannot be made reliable, document it as a **manual gate**
and keep Stage 1–3 as the automated requirement. Do not fake a PASS.

### Stage 5 — Release metadata check

- `SHA256SUMS` matches every asset.
- `Packages.gz` lists the same versions as the `.deb` files.
- `build-info.json` suite/arch/tags/commit match the workflow inputs.
- Release body links the exact `Install-Logs` summary artifact (not the logs
  themselves; those can contain local paths).

---

## 9. Publishing to GitHub Releases

Everything is hosted on the existing repository:
**<https://github.com/LinuxBeginnings/Debian-Hyprland/releases>**

### 9.1 Tag and asset naming

| Kind | Example | Mutability |
| --- | --- | --- |
| Rolling per-suite tag | `debs-trixie` | Assets replaced on every successful build (`gh release upload --clobber`) |
| Dated per-suite tag | `debs-trixie-2026.11.25` | Immutable; used for pinning and rollback |
| Asset | `hyprland-kool_0.57.2-1+trixie1_amd64.deb` | Per package |
| Index | `Packages.gz`, `Release`, `SHA256SUMS`, `build-info.json` | Per release |

Dated tags contain the suite in the name so a release page never mixes binaries for
different ABIs. Rolling tags give the consumer a stable URL without hitting the
GitHub API:

```
https://github.com/LinuxBeginnings/Debian-Hyprland/releases/download/debs-trixie/Packages.gz
https://github.com/LinuxBeginnings/Debian-Hyprland/releases/download/debs-trixie/SHA256SUMS
```

No `.deb` is ever committed to git. The repository stays a few MB.

### 9.2 What a user sees

Release title: `Hyprland .deb packages — trixie (2026-11-25)`
Release body (generated by `packaging/publish-debs.sh`):

```markdown
Prebuilt Hyprland stack for **Debian 13 (trixie)**, amd64.

| Component | Version | Package |
| --- | --- | --- |
| Hyprland | v0.57.2 | hyprland-kool |
| hyprutils | v0.14.4 | libhyprutils-kool5 |
| hyprlang | v0.6.8 | libhyprlang-kool2 |
| ... | ... | ... |

Built from commit `abc1234` of this repository with the tags above, in
`debian:trixie@sha256:...`. Tested by installing into a clean trixie container,
running `Hyprland --version`, sweeping `ldd`, then upgrading and purging.

Install:

    ./update-hyprland.sh --mode prebuilt

or pin this exact build:

    ./update-hyprland.sh --mode prebuilt --prebuilt-ref debs-trixie-2026.11.25

Verify:

    sha256sum -c SHA256SUMS

Not for forky/sid — use the `debs-forky` / `debs-sid` release.
Build logs: see the CI run linked below.
```

### 9.3 Workflow

`.github/workflows/build-debs.yml`:

```yaml
name: build-debs
on:
  workflow_dispatch:
    inputs:
      suites:
        description: "Comma-separated suites"
        default: "trixie,forky,sid"
  push:
    tags: ["debs-*"]
    paths:
      - "hypr-tags.env"
      - "install-scripts/**"
      - "packaging/**"
      - ".github/workflows/build-debs.yml"
  schedule:
    - cron: "0 4 * * 1"      # weekly drift check
permissions:
  contents: write
concurrency:
  group: build-debs-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - suite: trixie
            image: debian:trixie
          - suite: forky
            image: debian:forky
          - suite: sid
            image: debian:sid
    runs-on: ubuntu-24.04
    container:
      image: ${{ matrix.image }}
    steps:
      - uses: actions/checkout@v4
      - name: Prepare unprivileged builder
        run: |
          apt-get update
          apt-get install -y --no-install-recommends sudo git ca-certificates curl jq \
            dpkg-dev lintian apt-utils xz-utils file binutils
          useradd -m -s /bin/bash builder
          echo 'builder ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/builder
          git config --global --add safe.directory "$GITHUB_WORKSPACE"
      - name: Build + self-test packages
        run: |
          chown -R builder:builder "$GITHUB_WORKSPACE"
          sudo -u builder ./packaging/build-debs.sh --suite "${{ matrix.suite }}" --arch amd64
      - uses: actions/upload-artifact@v4
        with:
          name: debs-${{ matrix.suite }}-amd64
          path: packaging/out/${{ matrix.suite }}/amd64/
          if-no-files-found: error
```

`publish-debs.yml` (separate job so a publish failure never re-runs builds):

```yaml
name: publish-debs
on:
  workflow_run:
    workflows: [build-debs]
    types: [completed]
permissions:
  contents: write
jobs:
  publish:
    if: github.event.workflow_run.conclusion == 'success'
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/download-artifact@v4
      - run: ./packaging/publish-debs.sh --from-artifacts artifacts/
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

`publish-debs.sh` responsibilities:

1. Refuse to publish if any suite is missing or lacks `SHA256SUMS`/`Packages.gz`.
2. `gh release view debs-<suite>-<date> || gh release create ...` (immutable).
3. `gh release upload debs-<suite>-<date> *.deb Packages.gz Release SHA256SUMS build-info.json`.
4. `gh release view debs-<suite> || gh release create debs-<suite> --prerelease=false --notes "Rolling build"`,
   then `gh release upload debs-<suite> ... --clobber`.
5. Delete dated releases beyond the last 10 per suite (`gh release delete --cleanup-tag`),
   keeping at least one older build for rollback.
6. Optionally upload GitHub Artifact Attestations (`actions/attest-build-provenance`)
   so `gh attestation verify` works on the `.deb`.

### 9.4 Signing (deferred but planned)

- Generate a project key once; store the private key and passphrase as repository
  secrets (`DEB_GPG_PRIVATE_KEY`, `DEB_GPG_PASSPHRASE`).
- Sign `Release` → `InRelease`/`Release.gpg` for the APT channel.
- Publish the public key as `key.asc` asset and document
  `curl -fsSL .../key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/hyprland-kool.gpg`.
- Until then, `SHA256SUMS` + HTTPS is the integrity story, and the consumer says so
  explicitly.

### 9.5 Retention

| Channel | Keeps |
| --- | --- |
| Rolling tag `debs-<suite>` | current build only |
| Dated tags `debs-<suite>-<date>` | last 10 per suite (~10 × 150–300 MB) |
| `Packages.gz` in dated tags | frozen, so old installs keep resolving |
| CI artifacts | 14 days (default), never referenced by users |

---

## 10. Suggested distribution layouts

### Layout A — Releases only (recommended first step)

```
Debian-Hyprland/
├── packaging/                       # build + test tooling (this plan)
├── .github/workflows/build-debs.yml
├── .github/workflows/publish-debs.yml
└── (releases, not files)
    ├── debs-trixie                          -> latest trixie .deb set
    ├── debs-trixie-2026.11.25               -> frozen
    ├── debs-forky
    ├── debs-forky-2026.11.25
    ├── debs-sid
    └── debs-sid-2026.11.25
```

Consumer: `update-hyprland.sh --mode prebuilt` downloads the `.deb` files plus
`SHA256SUMS`, verifies, installs with `apt-get install ./*.deb`.

- **Pros:** zero extra infrastructure, no Pages limit, no signing needed to start,
  works with the repo users already have.
- **Cons:** not usable as `deb ...` line in `sources.list`; upgrades are driven by
  this repo's script, not by `apt upgrade`.

### Layout B — Releases + APT repository on `gh-pages`

```
Debian-Hyprland/
├── packaging/
│   ├── publish-debs.sh              # creates the release assets (as Layout A)
│   └── publish-apt.sh               # regenerates the APT tree
└── gh-pages branch (orphan)
    ├── key.asc
    ├── dists/
    │   ├── trixie/
    │   │   ├── InRelease            # signed
    │   │   ├── Release
    │   │   └── main/binary-amd64/{Packages,Packages.gz,Release}
    │   ├── forky/...
    │   └── sid/...
    └── pool/
        ├── trixie/main/h/hyprland-kool/*.deb
        ├── forky/main/h/hyprland-kool/*.deb
        └── sid/main/h/hyprland-kool/*.deb
```

Generated by:

```bash
apt-ftparchive packages pool/trixie > dists/trixie/main/binary-amd64/Packages
gzip -9c dists/trixie/main/binary-amd64/Packages > .../Packages.gz
apt-ftparchive -o APT::FTPArchive::Release::Suite=trixie \
               -o APT::FTPArchive::Release::Codename=trixie \
               -o APT::FTPArchive::Release::Architectures=amd64 \
               -o APT::FTPArchive::Release::Components=main \
               release dists/trixie > dists/trixie/Release
gpg --clearsign -o dists/trixie/InRelease dists/trixie/Release
```

User side:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://linuxbeginnings.github.io/Debian-Hyprland/key.asc \
  | sudo gpg --dearmor -o /etc/apt/keyrings/hyprland-kool.gpg
echo "deb [signed-by=/etc/apt/keyrings/hyprland-kool.gpg] \
https://linuxbeginnings.github.io/Debian-Hyprland trixie main" \
  | sudo tee /etc/apt/sources.list.d/hyprland-kool.list
sudo apt update && sudo apt install hyprland-kool-full
```

Pinning file `/etc/apt/preferences.d/hyprland-kool.pref`:

```
Package: *-kool
Pin: origin linuxbeginnings.github.io
Pin-Priority: 600
```

- **Pros:** `apt upgrade` keeps the stack current; standard Debian UX; supports
  `apt install hyprlock-kool` ad hoc.
- **Cons:** Pages has a ~1 GB site limit (keep only current builds there, history in
  Releases), needs signing for a good experience, one more publish step.

### Layout C — Separate artifacts repository

```
LinuxBeginnings/Debian-Hyprland-debs/
├── .github/workflows/build.yml       # checks out Debian-Hyprland at a ref, builds
├── dists/{trixie,forky,sid}/...
├── pool/{trixie,forky,sid}/...
├── scripts/build.sh                  # thin wrapper around packaging/build-debs.sh
└── README.md                         # user-facing install instructions
```

- **Pros:** publishes without touching `contents: write` on the main repo; clear
  separation between source and binaries; its own Pages site and release list.
- **Cons:** two repositories to keep in sync, two issue trackers, and the build code
  still lives in the main repo (workflow does `actions/checkout` of it), so debugging
  spans repos.

### Comparison

| Criterion | A: Releases only | B: Releases + Pages APT | C: separate repo |
| --- | --- | --- | --- |
| Setup effort | low | medium | medium |
| Consumption path | `update-hyprland.sh` | `apt` + `update-hyprland.sh` | either |
| Needs signing | no | strongly recommended | strongly recommended |
| `apt upgrade` support | no | yes | yes |
| Storage ceiling | Releases (~2 GiB/asset, no practical total) | Pages ~1 GB | Releases + Pages |
| Repo noise | none | orphan branch | separate repo |
| Recommended for | phase 1–3 | phase 4+ | only if Releases permissions are a problem |

**Recommendation:** ship Layout A first, keep `publish-debs.sh` structured so adding
`publish-apt.sh` (Layout B) is a pure addition, and treat Layout C as a fallback if
`contents: write` on the main repo is unacceptable.

---

## 11. Consumer integration

### 11.1 `update-hyprland.sh --mode prebuilt`

New mode alongside the existing `source` / `debian` / `auto`:

```
--mode prebuilt        Install tested .deb packages for this suite (fallback to source)
--prebuilt             Alias for --mode prebuilt
--prebuilt-ref REF     Pin a dated release tag (default: rolling debs-<suite>)
--prebuilt-only        Never fall back to source; fail if no tested build exists
--prebuilt-allow-unverified
                       Skip SHA256SUMS verification (loud warning)
```

Flow:

```
1. suite = detect_suite()            # trixie | forky | sid; refuse others
   arch  = dpkg --print-architecture
2. base  = https://github.com/LinuxBeginnings/Debian-Hyprland/releases/download
   ref   = ${PREBUILT_REF:-debs-<suite>}
3. fetch Packages.gz + SHA256SUMS to a temp dir (curl -fsSL, retry 3)
   - 404 -> "no tested build for <suite>/<arch>" -> fallback (unless --prebuilt-only)
4. parse Packages.gz -> pkg/version table; verify suite tag inside build-info.json
5. compare each package version with hypr-tags.env:
   - equal        -> install
   - asset older  -> source build for those modules (or --prebuilt-only => error)
   - asset newer  -> install (user is behind)
6. download selected .deb files; sha256sum -c SHA256SUMS
7. purge Debian hypr* packages (unless --keep-debian-hypr)
8. sudo apt-get install -y ./*.deb         # resolves Depends, handles upgrade
   (fallback: sudo dpkg -i ./*.deb && sudo apt-get -f install -y)
9. verify:
   - dpkg -l '*-kool' all 'ii'
   - /usr/local/bin/Hyprland --version matches HYPRLAND_TAG
   - ldd sweep over /usr/local/bin/* and /usr/local/lib/*.so* -> no "not found"
10. print summary + how to roll back (--prebuilt-ref <older dated tag>)
```

Details that matter:

- **No GitHub API dependency** in the default path (rolling tag = fixed URL), avoiding
  the 60 requests/hour unauthenticated limit. `--prebuilt-ref latest` may use the API.
- **`--only` / `--skip` map to packages** through `packaging/lib/deb-manifest.sh`
  (e.g. `--only hyprland,hyprpaper` → `hyprland-kool hyprpaper-kool` and their hard
  dependencies; apt pulls the `-kool` libs automatically).
- **`--dry-run` must work for prebuilt too**: print the resolved package list,
  versions and URLs, download nothing, install nothing.
- **Downgrades** are explicit: `--prebuilt-ref` to an older dated tag uses
  `--allow-downgrades` and prints a warning.
- **Fallback is per module, not per run, only if safe.** If a single package is
  missing, build only that module from source (`--only <module>`) *after* installing
  the packages that do exist, so the source build links the packaged libraries. If the
  missing module is a library, fall back to a full source run instead.
- **No mixing across suites.** `build-info.json` is checked; a trixie asset on forky
  is a hard error, not a warning.
- **`/usr/local` drift.** If `/usr/local/lib/libhypr*.so*` exists but no `-kool`
  package owns it, warn and offer `--package-cleanup` so `ldconfig` cannot pick a
  stale library.

### 11.2 `install.sh`

```bash
./install.sh --mode prebuilt            # non-interactive
./install.sh --prebuilt --preset preset.sh
```

- New wizard entry: "Install/Upgrade Hyprland from prebuilt .deb (fast, tested)" next
  to the existing source/Debian-package choices.
- Reuses `ensure_libinput_min_version_from_local_debs` for `debs/libinput-testing/`.
- Keeps the existing `--build-trixie`, `--force-reinstall` and `--packages` semantics;
  `--force-reinstall` becomes `apt-get install --reinstall`.

### 11.3 `dry-run-build.sh`

Add `--prebuilt` to verify the prebuilt channel without compiling:

```bash
./dry-run-build.sh --prebuilt                # report resolvable package versions per module
./dry-run-build.sh --prebuilt --suite trixie # check a suite other than the current one
```

Output mirrors the existing PASS/FAIL table: `PASS` = a tested package exists at the
pinned version, `FAIL` = missing/stale (would fall back to source).

### 11.4 Uninstall

```bash
sudo apt purge '*-kool' && sudo apt autoremove --purge -y
```

`uninstall.sh` gains a prebuilt branch that does exactly this and removes the
`/usr/local` leftovers a source build would have created (it already handles those).

---

## 12. Changes to existing files

| File | Change |
| --- | --- |
| `update-hyprland.sh` | `--mode prebuilt`, `--prebuilt*` flags, suite/arch detection reuse, version comparison against `hypr-tags.env`, fallback path, usage text. `DEFAULT_MODULES` unchanged (packaging order mirrors it). |
| `install.sh` | new mode + wizard option; `--mode prebuilt` parsing; reuse of the libinput helper. |
| `dry-run-build.sh` | `--prebuilt` / `--suite` checks, no `DEFAULT_MODULES` change. |
| `uninstall.sh` | purge `*-kool` branch. |
| `.gitignore` | ignore `packaging/out`, `packaging/stage`, `packaging/work`. |
| `README.md` | short "Prebuilt packages" section linking this document and the Releases page. |
| `Debian-Hyprland-Install-Upgrade.md` | upgrade path via `--mode prebuilt`, rollback via `--prebuilt-ref`. |
| `CHANGELOG.md` | entry under the current month when the first phase lands. |
| `AGENTS.md` | note the packaging pipeline in the workflow section (module ordering must be updated in `packaging/lib/deb-manifest.sh` too). |

Per `AGENTS.md`, any change to module ordering or options must update `install.sh`,
`update-hyprland.sh` (`DEFAULT_MODULES`) and `dry-run-build.sh`. Packaging adds a
fourth list (`packaging/lib/deb-manifest.sh`), which must be kept in sync — a CI check
comparing it with `DEFAULT_MODULES` prevents drift.

---

## 13. Phased implementation plan

| Phase | Deliverable | Acceptance criteria | Effort |
| --- | --- | --- | --- |
| 1 | `packaging/lib/*` + `build-debs.sh` for **one** suite (trixie) and **core only** (`hyprutils hyprlang hyprcursor aquamarine hyprgraphics hyprwire hyprland`) | `./packaging/build-debs.sh --suite trixie` produces 7 installable `.deb` files; `apt-get install ./*.deb` in a clean trixie container gives a working `Hyprland --version` | ~1 day |
| 2 | All 26 modules, manifests, split lib/dev packages, app modules | Full set installs and purges cleanly; `dpkg -c` matches manifests; no file outside allow-list | ~1 day |
| 3 | `build-debs.yml` matrix (trixie/forky/sid), artifact upload, `Install-Logs` bundle | Three green suites from a clean runner; failing suite publishes nothing | ~1 day |
| 4 | `publish-debs.sh`, Release A creation, `SHA256SUMS`, `build-info.json`, retention | First release page visible with correct assets; `sha256sum -c` passes after download | ~0.5 day |
| 5 | `--mode prebuilt` in `update-hyprland.sh` (+ `--prebuilt-ref`, `--prebuilt-only`, fallback, dry-run) | On a clean trixie VM: `--mode prebuilt` installs the stack in < 2 min, `Hyprland --version` matches the tag, no compilation; deleting the release makes it fall back to source | ~1 day |
| 6 | `install.sh` menu entry, `uninstall.sh` purge, `dry-run-build.sh --prebuilt`, docs + `CHANGELOG.md` | Wizard path works end-to-end; docs linked from README | ~0.5 day |
| 7 | Layout B: `publish-apt.sh`, `gh-pages` repo, GPG signing, pinning file, `key.asc` | `apt update && apt install hyprland-kool-full` works on all three suites with signature verification | ~1 day |
| 8 | arm64 matrix, artifact attestations, weekly drift job, optional `piuparts` | arm64 release exists; `gh attestation verify` passes; weekly job reports tag drift | ~1 day |

Total: roughly 5–7 working days for phases 1–6 (the usable end-to-end feature), plus
2 days for the APT channel and hardening.

### Ordering notes

- Phase 1 deliberately builds only the core so a trixie compile failure is found
  before any tooling around apps exists.
- Phases 3 and 4 stay separate: a build can be green and publishing still broken;
  keeping the publish step out of the build job prevents re-running a 40-minute build
  because of a token/permission error.
- Phase 5 must land before phase 6, otherwise users can select a mode in the wizard
  that does nothing.

---

## 14. Failure handling and rollback

| Situation | Behaviour |
| --- | --- |
| New tag fails to compile on trixie | CI job fails, dated release for trixie is not created, rolling tag keeps the last good build; users on trixie stay on the previous version |
| Only one module fails on one suite | Same: suite-level atomicity. No partial releases |
| Published package is broken after all (runtime regression) | Re-point the rolling tag to the previous dated asset set (`gh release upload --clobber` from the older release) and mark the bad dated release as a pre-release with a warning; users on `--prebuilt-ref` are unaffected |
| `SHA256SUMS` mismatch at install time | Hard abort, no install, suggest `--mode source` |
| Release deleted / GitHub outage | Consumer falls back to source build (unless `--prebuilt-only`) |
| Disk pressure on the runner | ccache + `--only` incremental builds; build logs trimmed before upload |
| Debian ships a newer hyprland than our pin | Prebuilt version wins for `/usr/local`, but warn; `/usr/bin/hyprctl` shadowing is avoided by the default purge policy |

---

## 15. Open decisions

1. **Maintainer address** for `control` files (must be a real, monitored address).
2. **Signed APT repo in phase 1 or phase 4?** Signing early is more work but avoids a
   later migration of user sources.
3. **`Conflicts: hyprland` by default?** The plan says no (co-installable), but users
   who never want Debian's package may prefer the strict variant.
4. **`xkbcommon`**: keep building it (pinned tag can be newer than Debian) or depend on
   `libxkbcommon0` from the suite? Recommend: depend by default, build only when the
   pin is newer.
5. **`hyprtavern` / `hyprwire` moving branches.** `HYPRWIRE_TAG=main` and
   `HYPRTAVERN_TAG=auto` mean non-reproducible inputs. Options: pin commit SHAs in
   `hypr-tags.env` for release builds, or accept and record the resolved SHA in
   `build-info.json` (recommended: both — record always, pin when publishing).
6. **arm64 now or later?** Later (phase 8) unless an arm64 user reports breakage.
7. **`debs/` naming.** `debs/libinput-testing/` already hosts vendored third-party
   debs; packaged Hyprland output goes to `packaging/out/` and Releases, never to
   `debs/`. Confirm this split in `packaging/README.md`.

---

## Appendix A — Module order, tags and packages

| # | Module | Tag variable | `.deb` |
| --- | --- | --- | --- |
| 1 | `xkbcommon` | (none; script default) | `libxkbcommon-kool0` (optional) |
| 2 | `hyprutils` | `HYPRUTILS_TAG` = v0.14.4 | `libhyprutils-kool<SONAME>` |
| 3 | `hyprlang` | `HYPRLANG_TAG` = v0.6.8 | `libhyprlang-kool<SONAME>` |
| 4 | `hyprcursor` | `HYPRCURSOR_TAG` = v0.1.14 | `libhyprcursor-kool<SONAME>` |
| 5 | `aquamarine` | `AQUAMARINE_TAG` = v0.16.0 | `libaquamarine-kool<SONAME>` |
| 6 | `hyprgraphics` | `HYPRGRAPHICS_TAG` = v0.7.0 | `libhyprgraphics-kool<SONAME>` |
| 7 | `hyprtoolkit` | `HYPRTOOLKIT_TAG` = v0.7.0 | `hyprtoolkit-kool` |
| 8 | `hyprwayland-scanner` | `HYPRWAYLAND_SCANNER_TAG` = v0.4.6 | `hyprwayland-scanner-kool` |
| 9 | `wayland-protocols-src` | `WAYLAND_PROTOCOLS_TAG` = 1.50 | `wayland-protocols-kool` |
| 10 | `hyprland-protocols` | `HYPRLAND_PROTOCOLS_TAG` = v0.8.0 | `hyprland-protocols-kool` |
| 11 | `hyprland-qt-support` | `HYPRLAND_QT_SUPPORT_TAG` = v0.1.0 | `hyprland-qt-support-kool` |
| 12 | `hyprland-guiutils` | `HYPRLAND_GUIUTILS_TAG` = v0.2.2 | `hyprland-guiutils-kool` |
| 13 | `hyprwire` | `HYPRWIRE_TAG` = main | `libhyprwire-kool<SONAME>` |
| 14 | `hyprwire-protocols` | `HYPRWIRE_PROTOCOLS_TAG` = hyprtavern | `hyprwire-protocols-kool` |
| 15 | `hyprland` | `HYPRLAND_TAG` = v0.57.2 | `hyprland-kool` |
| 16 | `hypridle` | `HYPRIDLE_TAG` = v0.1.8 | `hypridle-kool` |
| 17 | `hyprlock` | `HYPRLOCK_TAG` = v0.9.7 | `hyprlock-kool` |
| 18 | `hyprpaper` | `HYPRPAPER_TAG` = v0.8.5 | `hyprpaper-kool` |
| 19 | `hyprpicker` | `HYPRPICKER_TAG` = v0.4.8 | `hyprpicker-kool` |
| 20 | `hyprpolkitagent` | `HYPRPOLKITAGENT_TAG` = v0.2.0 | `hyprpolkitagent-kool` |
| 21 | `hyprshutdown` | `HYPRSHUTDOWN_TAG` = v0.1.2 | `hyprshutdown-kool` |
| 22 | `hyprpwcenter` | `HYPRPWCENTER_TAG` = v0.1.2 | `hyprpwcenter-kool` |
| 23 | `hyprtavern` | `HYPRTAVERN_TAG` = auto | `hyprtavern-kool` |
| 24 | `hyprsunset` | `HYPRSUNSET_TAG` = v0.4.0 | `hyprsunset-kool` |
| 25 | `hyprlauncher` | `HYPRLAUNCHER_TAG` = v0.1.7 | `hyprlauncher-kool` |
| 26 | `hyprsysteminfo` | `HYPRSYSTEMINFO_TAG` = v0.2.0 | `hyprsysteminfo-kool` |

(`XDPH_TAG` = v1.5.0 is installed by `install-scripts/xdph.sh`, which is not part of
`DEFAULT_MODULES`; add `xdg-desktop-portal-hyprland-kool` in phase 2 if users ask for
a prebuilt portal too.)

## Appendix B — `Packages.gz` and `Release` examples

`Packages` stanza:

```
Package: hyprpaper-kool
Version: 0.8.5-1+trixie1
Architecture: amd64
Maintainer: LinuxBeginnings <maintainer-address>
Installed-Size: 412
Depends: libc6 (>= 2.38), libstdc++6 (>= 13), libwayland-client0, libmagic1,
 libhyprutils-kool5 (>= 0.14.4), libhyprlang-kool2 (>= 0.6.8)
Filename: ./hyprpaper-kool_0.8.5-1+trixie1_amd64.deb
Size: 98432
MD5sum: ...
SHA256: ...
Section: x11
Priority: optional
Description: KooL Hyprpaper build (upstream v0.8.5, source-patched)
```

`release` for `apt-ftparchive`:

```
Origin: LinuxBeginnings
Label: Debian-Hyprland
Suite: trixie
Codename: trixie
Architectures: amd64
Components: main
Description: Prebuilt Hyprland stack for Debian 13 (trixie)
Date: Wed, 25 Nov 2026 04:12:00 UTC
```

## Appendix C — Command cheat sheet

```bash
# local build, single suite, core only
./packaging/build-debs.sh --suite trixie --only hyprutils,hyprlang,hyprcursor,aquamarine,hyprgraphics,hyprwire,hyprland

# full stack, one suite
./packaging/build-debs.sh --suite forky

# inspect a package
dpkg-deb -I packaging/out/trixie/amd64/hyprland-kool_*_amd64.deb
dpkg-deb -c packaging/out/trixie/amd64/hyprland-kool_*_amd64.deb | head -40

# check runtime deps were computed, not guessed
dpkg-deb -f packaging/out/trixie/amd64/hyprpaper-kool_*_amd64.deb Depends

# clean-container install test
docker run --rm -v "$PWD/packaging/out/trixie/amd64:/debs:ro" debian:trixie \
  bash -c 'apt-get update && apt-get install -y --no-install-recommends /debs/*.deb && Hyprland --version'

# publish (after a green build)
./packaging/publish-debs.sh --suite trixie --date 2026.11.25

# consumer paths
./update-hyprland.sh --mode prebuilt
./update-hyprland.sh --mode prebuilt --prebuilt-ref debs-trixie-2026.11.25
./update-hyprland.sh --mode prebuilt --prebuilt-only --dry-run
```

## Appendix D — Anti-patterns to avoid

- Committing `.deb` files to git (repo bloat, no suite separation, no signing).
- One `debian/` directory per upstream repo (26 vendored packaging trees to maintain;
  the per-tag patch logic in `install-scripts/` is the actual value here).
- Building once and publishing to all three suites. The suites have different
  `libstdc++`, `libabsl`, `libdisplay-info`, `libjxl` and `libmagic` ABIs.
- Hand-writing `Depends`. Use `dpkg-shlibdeps` inside the target container.
- Publishing without installing the artefacts in a clean container first.
- Installing to `/opt/kool` while source builds use `/usr/local` (two divergent
  installations, detection logic breaks).
- Overloading `--mode debian` (which means "Debian's distro packages") with prebuilt
  packages. A separate `prebuilt` mode keeps both meanings unambiguous.
