---
name: omarchy-jetson
description: Diagnose and operate NVIDIA Jetson, CUDA, power, storage, display, browser/Electron and Arch Linux ARM components on the Omarchy Jetson system. Use for Jetson hardware or platform work, and for apps that misbehave only on this hardware; use the separate omarchy skill for ordinary desktop customization.
---

# Omarchy Jetson platform

This is an AGX Orin 64 GB running Arch Linux ARM from NVMe through NVIDIA's
Jetson Linux R39.2.1 firmware, kernel, DTB, and userspace boundary. It is not
Ubuntu: use `pacman`, never `apt`, and do not infer package compatibility from
an Ubuntu JetPack guide.

The desktop is upstream Omarchy (the `omarchy` and `omarchy-settings` packages
from the `[omarchy]` repo) with a thin Jetson layer on top:
`omarchy-jetson-upstream` puts hardware overrides ahead of `/usr/bin` on PATH
(`/usr/lib/omarchy-jetson/bin`) and runs the shell through the managed
`omarchy-jetson-shell` user service. Fix desktop behaviour in upstream's terms
first; add an override only for something the Jetson needs.

## Invariants

- Do not read, mount, format, benchmark, cache on, or otherwise use eMMC. Treat
  NVMe as the only storage unless the user explicitly changes that scope.
- Jetson uses an integrated NVGPU and unified system memory. `nvidia-smi` and
  discrete-GPU VRAM terminology are not authoritative here.
- Prefer installed project commands and signed Arch ARM packages. Do not replace
  the pinned NVIDIA BSP boundary with generic Arch NVIDIA drivers. The kernel is
  `linux-jetson`; `linux-aarch64` is held in `IgnorePkg` because it also claims
  `/boot/Image`. Never let a generic kernel install over the Jetson one.
- Observe first. Ask immediately before flashing, changing power mode, rebooting,
  changing privilege, touching the kernel, `/boot` or NVIDIA packages, or another
  consequential mutation.

## Read-only diagnostics

Identify the platform without probing storage devices:

```bash
uname -m
tr -d '\0' </proc/device-tree/model
findmnt -no SOURCE,FSTYPE,OPTIONS /
pacman -Q linux-jetson nvidia-jetson-userspace nvidia-jetson-cuda omarchy
```

Inspect the NVIDIA power table and current state through the guarded adapter:

```bash
omarchy-jetson-power status
```

Use `wpctl status`, `bluetoothctl list`, `hyprctl monitors -j`, and
`systemctl --user --failed` for desktop integration. For GPU/CUDA validation,
prefer the installed CUDA `deviceQuery` known-answer binary; never treat
library presence alone as proof that a CUDA kernel ran.

## Display

Output is the Tegra DRM/KMS driver (connector `DP-1`) driven by Hyprland;
`omarchy-jetson-display` changes resolution and scale.

- Supported modes come from the screen's EDID, capped by the link. A passive
  DP→HDMI (DP++) adapter caps out at about 1080p60 (165 MHz TMDS), so a missing
  high mode usually means the cable or adapter, not the driver. Compare
  `hyprctl monitors all` `availableModes` before and after a cable change.
- `grim` screenshots show the framebuffer, not what the panel displays.
  Overscan, blanking and colour problems can't be seen in a screenshot; ask the
  user.
- Before applying an untested mode, arm an automatic revert. The Jetson has no
  other display to recover from a black screen.

## Chromium, Electron and video

- Chromium GPU compositing crashes under native Wayland on Tegra
  (`eglCreateImage` 0x300C on dma-buf import) and the browser silently falls
  back to software rendering. Keep GPU raster and video, and pass
  `--disable-gpu-compositing` in the user's `~/.config/chromium-flags.conf`,
  `brave-flags.conf` and `electron*-flags.conf`. The base build doesn't seed
  these yet.
- CPU compositing can't keep up with video at 4K. For a video-heavy app,
  run it through XWayland (`--ozone-platform=x11`) with
  `--force-device-scale-factor` set to the monitor's scale, and set Hyprland's
  `xwayland:force_zero_scaling` so the app scales itself.
- DRM video (Widevine): Google publishes no Linux ARM64 Widevine CDM, so
  Chromium's component updater leaves `WidevineCdm` empty and DRM sites refuse
  to play. The only route is the ChromeOS ARM64 CDM (the Asahi Linux
  `widevine-installer` method). It is not part of this build: it's the user's
  choice, unofficial and L3 (streaming services cap it at SD). Brave's ARM64
  build also lacks an AAC decoder, so AAC-audio services play silently there.
  Use Chromium for them.

## Sandboxing and tools

- The Jetson kernel sets `kernel.apparmor_restrict_unprivileged_userns=1`.
  bubblewrap (glycin image loaders, GTK file chooser, portals) needs the
  `bwrap` AppArmor profile from `omarchy-jetson-session`. Downloads failing or
  the file chooser crashing usually means that profile isn't loaded
  (`aa-status | grep bwrap`).
- CLI and developer tools come from `mise`, not pacman, unless an Omarchy or
  system package depends on them. systemd units don't see the login shell's PATH:
  a unit that runs a mise tool needs `%h/.local/share/mise/shims` on its PATH.
  Before removing a pacman tool, grep the systemd units for it.

## Logs and failure reports

Keep diagnostics bounded and secret-free. Relevant journal tags are
`omarchy-menu`, `omarchy-jetson-display`, `omarchy-jetson-power`,
`omarchy-jetson-upstream`, `omarchy-system-lock`, and `omarchy-jetson-idle`.
Report architecture, kernel,
BSP/package versions, exact failing command, status, and the smallest relevant
journal window. Use the `diagnose-crash` skill for a recorded core dump.

When a command is absent, distinguish an intentionally excluded desktop app
from a missing core capability. Never install an x86_64 binary or silently add
an Ubuntu container to make a platform check pass.

## Changing this project

Work in the omarchy-jetson repository. Run `make check` (the regression suites,
ShellCheck and the public-hygiene scan) before committing. A change to a
package bumps its `pkgrel` and keeps its `sha256sums` current. The pinned
upstream Omarchy release is `pkgver` in `packages/omarchy-jetson-upstream`.
