# Architecture

## Ownership boundaries

NVIDIA owns the hardware-enablement layer:

- QSPI firmware and UEFI
- board configuration and device trees
- Jetson Linux kernel and out-of-tree modules
- GPU/display selection services
- Tegra firmware, power, thermal, multimedia, and camera components
- CUDA, cuDNN, TensorRT, VPI, and container-runtime integration

Arch Linux ARM owns the general userspace:

- systemd and core utilities
- pacman and the AArch64 package repository
- networking, SSH, development tools, Docker, and desktop packages

This project owns the integration boundary:

- reproducible input manifests and verification
- Arch packages for NVIDIA-provided files that must exist on the host
- service and library integration without untracked file copies
- update holds and compatibility tests
- Omarchy desktop selection and adaptation
- recovery documentation

## Initial boot design

The first image retains NVIDIA's exact 39.2.1 kernel, modules, DTBs, firmware,
and boot flow. The generic Arch Linux ARM rootfs replaces NVIDIA's sample
Ubuntu rootfs. NVIDIA userspace files are inventoried and packaged rather than
blindly applied.

The target NVMe will contain the root filesystem. It currently contains an ext4
filesystem mounted at `/storage`, so it must not be repartitioned or formatted
until its contents and backup status are confirmed. The user reports eMMC
instability, although its device health counters presently report normal. eMMC
is excluded from swap and cache while kernel I/O history is investigated. Swap
policy is zram with low swappiness; optional encrypted NVMe swap is deferred
until storage health and workload behavior are measured.

## Update model

The following packages are treated as one tested compatibility set:

- kernel and kernel headers
- NVIDIA kernel modules
- firmware and device trees
- EGL/GBM/Vulkan libraries
- CUDA and the NVIDIA container runtime

Arch userspace updates are tested against that set before promotion. Generic
Arch kernel and NVIDIA desktop-driver packages must not replace Jetson-owned
packages.

## Desktop layering

Desktop work begins only after the console/GPU milestone passes:

1. PipeWire, seat/session services, Wayland, and XWayland
2. Hyprland with a minimal known-good configuration
3. upstream Omarchy's shell (packages `omarchy` and `omarchy-settings` from
   upstream's signed aarch64 repository) on native AArch64 Quickshell as the
   sole bar, matching upstream, which ships no Waybar
4. themes, launchers, terminals, notifications, and portals
5. selected Omarchy commands, excluding Arch-install and boot-management code

Each layer receives a bounded launch test so graphics failures can be located.
