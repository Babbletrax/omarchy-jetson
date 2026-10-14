# Omarchy Jetson

This machine is an NVIDIA Jetson AGX Orin running Arch Linux ARM from NVMe with
upstream Omarchy on top. It is not Ubuntu: use `pacman`, never `apt`. It uses
NVIDIA's Tegra kernel and Jetson userspace, CUDA 13.2, Hyprland/Wayland, Foot,
Docker and systemd.

- Use the `omarchy` skill for desktop customization and the `omarchy-jetson`
  skill for Arch ARM/NVIDIA platform work.
- Voxtype provides offline dictation: hold F9, or toggle with Super+Ctrl+X.
- Do not use or modify the eMMC. The NVMe root is the only storage in scope
  unless the human explicitly says otherwise.
- Never replace the Jetson kernel, DTB, bootloader or NVIDIA packages with
  generic Arch packages. Update with `omarchy-update`.
- Ask before credentials, sending/publishing, purchases, deletion, privilege
  elevation, flashing, or other externally consequential actions.
