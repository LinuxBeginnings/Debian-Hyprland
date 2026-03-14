# Triage Issues with NVIDIA on Linux
<div align="center">
<h3>🧰 Common Issues & Fixes for NVIDIA on Linux</h3>
<p><em>Based on the KoolDots project (LinuxBeginnings), with solutions that apply broadly to Linux distributions.</em></p>
</div>

> **Preface**
> This document collects **common NVIDIA-related issues and fixes on Linux**, especially on hybrid Intel/NVIDIA laptops.  
> It is **inspired by the KoolDots project** [LinuxBeginnings](https://github.com/LinuxBeginnings) but **the steps and fixes are generally applicable** across Linux distros.  
> Some file locations and names may differ on your system—adjust paths accordingly.

---

## 📌 Versioning
**Current Version:** `2026.03.13`  
**Change History**
- `2026.03.13` — Initial release: SDDM external display issue, post-update external display loss.
- `2026.03.13` — Added trimmed command outputs and “missing output” hints for triage.
- `2026.03.13` — Added SDDM journal and Xorg log example outputs.
- `2026.03.13` — Added xrandr, nvidia-smi, and journal example outputs.

---

## 🧭 Table of Contents
- [🎛️ SDDM](#️-sddm)
  - [Issue 1: SDDM login screen only shows on internal (eDP-1) display (Hybrid Intel/NVIDIA)](#issue-1-sddm-login-screen-only-shows-on-internal-edp-1-display-hybrid-intelnvidia)
- [🧱 Driver / Kernel / Upgrade](#-driver--kernel--upgrade)
  - [Issue 2: After reboot or update, external display no longer works](#issue-2-after-reboot-or-update-external-display-no-longer-works)

---

# 🎛️ SDDM
All SDDM issues/fixes go in this section.

## Issue 1: SDDM login screen only shows on internal (eDP-1) display (Hybrid Intel/NVIDIA)

**Symptom**
- The SDDM greeter appears only on the internal panel (`eDP-1`), even though the external monitor works after logging into Hyprland.

**Test system used for this document**
- **OS:** Debian (testing/unstable lineage)
- **Kernel:** `6.19.6+deb14-amd64`
- **GPU (iGPU):** Intel UHD 630 (i915)
- **GPU (dGPU):** NVIDIA GTX 1660 Ti Mobile (TU116M)
- **NVIDIA Driver:** `595.45.04`
- **Display:** HDMI external monitor (also applicable to DP and USB‑C → DP/HDMI adapters)

### ✅ Triage commands (run as-is)
```bash
# See what connectors the kernel exposes
ls -l /sys/class/drm | grep -E "card|DP|HDMI|eDP"

# Check current SDDM display server configuration
cat /etc/sddm.conf 2>/dev/null
cat /etc/sddm.conf.d/*.conf 2>/dev/null

# Inspect SDDM Xsetup hooks (where display is configured)
cat /etc/sddm/Xsetup 2>/dev/null
cat /usr/share/sddm/scripts/Xsetup 2>/dev/null

# Check SDDM logs and Xorg log used by greeter
sudo journalctl -u sddm -b --no-pager | tail -n 200
sudo cat /var/log/Xorg.0.log | tail -n +1
```

### Example output (trimmed)
```text
lrwxrwxrwx    - root 13 Mar 15:32 card0 -> ../../devices/pci0000:00/0000:00:01.0/0000:01:00.0/drm/card0
lrwxrwxrwx    - root 13 Mar 15:32 card0-DP-1 -> ../../devices/pci0000:00/0000:00:01.0/0000:01:00.0/drm/card0/card0-DP-1
lrwxrwxrwx    - root 13 Mar 15:32 card0-DP-2 -> ../../devices/pci0000:00/0000:00:01.0/0000:01:00.0/drm/card0/card0-DP-2
lrwxrwxrwx    - root 13 Mar 15:32 card0-HDMI-A-1 -> ../../devices/pci0000:00/0000:00:01.0/0000:01:00.0/drm/card0/card0-HDMI-A-1
lrwxrwxrwx    - root 13 Mar 15:32 card1 -> ../../devices/pci0000:00/0000:00:02.0/drm/card1
lrwxrwxrwx    - root 13 Mar 15:32 card1-eDP-1 -> ../../devices/pci0000:00/0000:00:02.0/drm/card1/card1-eDP-1
```

### Example output (SDDM config, trimmed)
```text
[Theme]
Current=simple_sddm_2

[General]
DisplayServer=x11
InputMethod=qtvirtualkeyboard

[X11]
DisplayCommand=/etc/sddm/Xsetup
```

### Example output (SDDM journal, trimmed)
```text
Mar 13 04:17:32 prometheus sddm[1190]: Display server starting...
Mar 13 04:17:32 prometheus sddm[1190]: Running: /usr/bin/X -nolisten tcp -background none -seat seat0 vt2 -auth /run/sddm/xauth_jjRloI -noreset -displayfd 18
Mar 13 04:17:35 prometheus sddm[1190]: Running display setup script  "/etc/sddm/Xsetup"
Mar 13 04:17:35 prometheus sddm[1190]: Display server started.
Mar 13 04:17:36 prometheus sddm-helper[9850]: Starting X11 session: "" "/usr/bin/sddm-greeter-qt6 --socket /tmp/sddm-:0-IlognW --theme /usr/share/sddm/themes/simple_sddm_2"
Mar 13 04:17:48 prometheus sddm[1190]: Authentication for user  "dwilliams"  successful
Mar 13 04:17:48 prometheus sddm-helper[9966]: Starting Wayland user session: "/etc/sddm/wayland-session" "/usr/local/bin/start-hyprland"
```

### Example output (Xorg, trimmed)
```text
(--) NVIDIA(GPU-0): DELL S2721HS (DFP-4): connected
(--) NVIDIA(GPU-0): DELL S2721HS (DFP-4): Internal TMDS
(--) NVIDIA(GPU-0): DELL S2721HS (DFP-4): 600.0 MHz maximum pixel clock
```

### Example output (xrandr --query, trimmed)
```text
Screen 0: minimum 16 x 16, current 1920 x 1080, maximum 32767 x 32767
HDMI-A-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 600mm x 340mm
   1920x1080     74.91*+
   1280x720      74.78
```

### 📌 What you’re looking for
- **Xorg log shows external output connected** (e.g., NVIDIA `DFP-4`, `DP-1`, `HDMI-1-0`, etc.).
- **Xsetup** is actually run and can see output names via `xrandr`.
- **If `/sys/class/drm` only lists `eDP-1`, the external connector is not being detected.**

### ✅ Fix: make SDDM enable the first connected external output (dynamic)
> The greeter uses Xorg and `xrandr`.  
> On NVIDIA, output names often differ from i915 names (e.g., `DFP-*`, `HDMI-1-0`, etc.).  
> A hard-coded HDMI output name can fail. This script enables **whatever external output is connected**.

**Script (example)**
```bash
#!/bin/sh
# Xsetup - run as root before the login dialog appears

LOG=/var/log/sddm-xsetup.log
{
  echo "==== $(date -Is) Xsetup start ===="
  if [ -e /sbin/prime-offload ]; then
      echo "running NVIDIA Prime setup /sbin/prime-offload"
      /sbin/prime-offload
  fi

  xrandr --listproviders
  xrandr --query

  PRIMARY="eDP-1"
  EXT="$(xrandr --query | awk '/ connected/ {print $1}' | grep -v "^${PRIMARY}$" | head -n1)"

  if [ -n "$EXT" ]; then
    echo "Enabling external output: $EXT"
    xrandr --output "$PRIMARY" --auto --primary
    xrandr --output "$EXT" --auto --right-of "$PRIMARY" --primary
  else
    echo "No external output detected by xrandr"
  fi
  echo "==== $(date -Is) Xsetup end ===="
} >> "$LOG" 2>&1
```

**Notes**
- Some distros use `/etc/sddm/Xsetup` while others use `/usr/share/sddm/scripts/Xsetup`.
- Make sure the configured `DisplayCommand` points to the correct script:
  - `/etc/sddm.conf` or `/etc/sddm.conf.d/*.conf`
- Output names vary:
  - Intel: `eDP-1`, `DP-1`, `HDMI-1`
  - NVIDIA (Xorg): `DFP-4`, `HDMI-1-0`, `DP-1-0`, etc.
- USB‑C docks with DisplayLink may **not** appear in Xorg without DisplayLink/evdi drivers.

### Example output (abbreviated)
```text
NVIDIA GPU NVIDIA GeForce GTX 1660 Ti (TU116-A) at PCI:1:0:0
DFP-4 (DELL S2721HS): connected
eDP-1: connected
```

---

# 🧱 Driver / Kernel / Upgrade
All driver/kernel/update issues go in this section.

## Issue 2: After reboot or update, external display no longer works

**Symptom**
- External display worked previously but disappears after kernel update/reboot.
- `/sys/class/drm` shows only internal `eDP-1`.

**Root cause (common)**
- NVIDIA driver not loaded after kernel update.
- DKMS build failed or packages were removed.

### ✅ Triage commands (Debian example)
```bash
# Check installed NVIDIA packages and DKMS
dpkg -l | grep -E "nvidia-open|cuda-drivers|nvidia-driver|dkms"

# Check loaded modules
lsmod | grep -E "nvidia|i915"

# Check where the NVIDIA module is coming from
modinfo nvidia | head -n 5

# DKMS status/logs (if used)
sudo dkms status
sudo journalctl -b -u dkms --no-pager
sudo journalctl -b -u systemd-modules-load --no-pager
```

### Example output (abbreviated)
```text
ii  dkms                                              3.3.0-1                                   all          Dynamic Kernel Module System (DKMS)
ii  nvidia-driver                                     595.45.04-1                               amd64        NVIDIA metapackage
ii  nvidia-driver-cuda                                595.45.04-1                               amd64        NVIDIA driver CUDA integration components
ii  nvidia-driver-libs:amd64                          595.45.04-1                               amd64        NVIDIA metapackage (OpenGL/GLX/EGL/GLES libraries)
ii  nvidia-kernel-open-dkms                           595.45.04-1                               amd64        NVIDIA binary kernel module DKMS source open flavor
ii  nvidia-open                                       595.45.04-1                               amd64        NVIDIA Driver meta-package, Open GPU kernel modules, latest version
ii  nvidia-opencl-icd:amd64                           595.45.04-1                               amd64        NVIDIA OpenCL installable client driver (ICD)
```
**If NVIDIA packages are missing here, the driver is not installed or was removed.**

### Example output (modules + DKMS)
```text
nvidia_uvm           2154496  0
i915                 5079040  54
nvidia_drm            151552  18
nvidia_modeset       2170880  8 nvidia_drm
nvidia              16347136  111 nvidia_uvm,nvidia_modeset
filename:       /lib/modules/6.19.6+deb14-amd64/updates/dkms/nvidia.ko.xz
version:        595.45.04
nvidia/595.45.04, 6.18.15+deb14-amd64, x86_64: installed
nvidia/595.45.04, 6.19.6+deb14-amd64, x86_64: installed
```

**If `lsmod` shows no `nvidia*` entries, the driver is not loaded.**

### Example output (nvidia-smi, trimmed)
```text
NVIDIA-SMI 595.45.04              Driver Version: 595.45.04      CUDA Version: 13.2
|   0  NVIDIA GeForce GTX 1660 Ti     On  |   00000000:01:00.0  On |
| N/A   47C    P8              9W /   80W |      66MiB /   6144MiB |
```

### Example output (DKMS + modules-load journals, trimmed)
```text
-- No entries --
```
**If `journalctl -u dkms` is empty, there was no DKMS activity this boot (or DKMS isn’t installed).**

### ✅ Fix (Debian + KoolDots)
Use the provided installer (recommended):
```bash
install-scripts/nvidia.sh
```

**Modes**
```bash
install-scripts/nvidia.sh --mode=open     # Open kernel modules (recommended for Wayland)
install-scripts/nvidia.sh --mode=nvidia   # Proprietary CUDA drivers
install-scripts/nvidia.sh --mode=debian   # Debian-packaged drivers (older)
```

### ✅ Manual recovery (generic Linux)
If you don’t use KoolDots or Debian:
1. Reinstall NVIDIA driver packages for your distro.
2. Rebuild kernel modules (if DKMS is used).
3. Update initramfs.
4. Reboot.

**Generic DKMS rebuild example**
```bash
sudo dkms autoinstall -k "$(uname -r)"
sudo update-initramfs -u -k "$(uname -r)"
sudo modprobe nvidia nvidia_modeset nvidia_uvm nvidia_drm
```

**Legacy GPU note**
- Some older NVIDIA GPUs **cannot use the newest driver branches**.
- On those systems, install the **legacy driver series** recommended by your distro (often labeled `nvidia-legacy-xxx` or a versioned branch).
- If the current driver fails to load or is unsupported, check your distro’s NVIDIA compatibility matrix and install the matching legacy package.

---

## 🧩 Other SDDM locations to check
- `/etc/sddm.conf`
- `/etc/sddm.conf.d/*.conf`
- `/etc/sddm/Xsetup`
- `/usr/share/sddm/scripts/Xsetup`
- `/var/log/Xorg.0.log`
- `journalctl -u sddm -b`

---

**End of document**  
If you add a new category later (e.g., Installation, Upgrade, Wayland), append it to the Table of Contents and create a new top-level section.
