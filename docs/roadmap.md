# Roadmap

This historical engineering roadmap is superseded as the active tracker by
[delivery-checklist.md](delivery-checklist.md). Architecture-independent
keyboard compatibility is defined in
[shortcut-contract.md](shortcut-contract.md). Keep the phase history below for
provenance; do not use its unchecked boxes as the current machine status.

## Phase 0 — repository and evidence

- [x] pin the initial Jetson Linux/JetPack baseline
- [x] define ownership and safety boundaries
- [x] add read-only host and target inventory tools
- [x] capture a real target inventory
- [ ] record recovery and current-boot evidence
- [x] capture privileged NVMe SMART data and eMMC kernel error history
- [x] confirm backup/disposition and erase authorization for NVMe `/storage`
- [x] resolve initial immutable source artifacts and hashes

## Phase 1 — rootfs assembly

- [x] construct a generic Arch Linux ARM rootfs in a disposable workspace
- [x] remove default credentials and leave machine identity/SSH keys for first boot
- [x] inventory NVIDIA raw payload groups and select the Orin NVGPU variant
- [x] create Pacman packages for the minimum boot/GPU payload
- [x] install packaged NVIDIA kernel, initrd, modules, firmware, and DTB into a disposable rootfs
- [x] validate rootfs structure without executing target business logic

## Phase 2 — NVMe console boot

- [ ] prove the recovery path
- [ ] boot the guarded removable-USB test image without modifying the Jetson
- [ ] stage and flash only the explicitly selected NVMe target
- [ ] boot to multi-user console
- [ ] validate systemd, network, storage, GPU, and CUDA
- [ ] confirm eMMC receives no routine I/O

## Phase 3 — development base

- [ ] Docker and NVIDIA Container Toolkit
- [ ] GPU container known-answer test
- [ ] Python, virtual environments, and development headers
- [ ] VS Code ARM64
- [ ] NVIDIA Jetson device skills

## Phase 4 — Omarchy desktop

- [ ] minimal Hyprland session
- [ ] graphics and hardware-video validation
- [ ] Quickshell and Omarchy Shell
- [ ] portals, audio, notifications, lock, idle, and display management
- [ ] themes and selected Omarchy commands
- [ ] Omarchy skill adapted to installed paths and supported commands

## Phase 5 — maintenance

- [ ] signed project package repository
- [ ] compatibility-tested update channel
- [ ] filesystem snapshots and rollback
- [ ] reproducible recovery image
- [ ] documented upgrade qualification matrix
