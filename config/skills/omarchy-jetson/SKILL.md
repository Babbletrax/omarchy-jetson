---
name: omarchy-jetson
description: Diagnose and operate NVIDIA Jetson, CUDA, power, storage, and Arch Linux ARM components on the Omarchy Jetson system. Use for Jetson hardware or platform work; use the separate omarchy skill for ordinary desktop customization.
---

# Omarchy Jetson platform

This is an AGX Orin 64 GB running Arch Linux ARM from NVMe through NVIDIA's
Jetson Linux R39.2.1 firmware, kernel, DTB, and userspace boundary. It is not
Ubuntu: use `pacman`, never `apt`, and do not infer package compatibility from
an Ubuntu JetPack guide.

## Invariants

- Do not read, mount, format, benchmark, cache on, or otherwise use eMMC. Treat
  NVMe as the only storage unless the user explicitly changes that scope.
- Jetson uses an integrated NVGPU and unified system memory. `nvidia-smi` and
  discrete-GPU VRAM terminology are not authoritative here.
- Prefer installed project commands and signed Arch ARM packages. Do not replace
  the pinned NVIDIA BSP boundary with generic Arch NVIDIA drivers.
- Observe first. Ask immediately before flashing, changing power mode, rebooting,
  changing privilege, or another consequential mutation.

## Read-only diagnostics

Identify the platform without probing storage devices:

```bash
uname -m
tr -d '\0' </proc/device-tree/model
findmnt -no SOURCE,FSTYPE,OPTIONS /
pacman -Q linux-jetson nvidia-jetson-userspace nvidia-jetson-cuda
```

Inspect the NVIDIA power table and current state through the guarded adapter:

```bash
omarchy-jetson-power status
```

Use `wpctl status`, `bluetoothctl list`, `hyprctl monitors -j`, and
`systemctl --user --failed` for desktop integration. For GPU/CUDA validation,
prefer the installed CUDA `deviceQuery` known-answer binary; never treat
library presence alone as proof that a CUDA kernel ran.

## Logs and failure reports

Keep diagnostics bounded and secret-free. Relevant journal tags are
`omarchy-menu`, `omarchy-jetson-display`, `omarchy-jetson-power`,
`omarchy-system-lock`, and `omarchy-jetson-idle`. Report architecture, kernel,
BSP/package versions, exact failing command, status, and the smallest relevant
journal window. Use `coredumpctl` for a recorded core dump.

When a command is absent, distinguish an intentionally excluded desktop app
from a missing core capability. Never install an x86_64 binary or silently add
an Ubuntu container to make a platform check pass.
