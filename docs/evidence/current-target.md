# Current target evidence

Inventory captured read-only on 2026-09-01. The raw report is retained locally
under the ignored `reports/` directory because it includes device serials.

## Post-install state — 2026-09-03

The reference system now reports Arch Linux ARM on AArch64 with NVIDIA kernel
`6.8.12-1021-tegra`. `/dev/nvme0n1p1` is the ext4 root filesystem. No eMMC
partition is mounted. Bounded system and user failed-unit queries both returned
zero. Installed platform packages include `linux-jetson 6.8.12.1021-2`,
`nvidia-jetson-userspace 39.2.1-6`, CUDA 13.2.86, NVIDIA Container Toolkit
1.19.1-6, and the guarded recovery snapshot package.

The sections below preserve the pre-install Ubuntu/eMMC inventory rather than
silently rewriting historical evidence.

## Confirmed identity

- Model: NVIDIA Jetson AGX Orin Developer Kit
- Module: production AGX Orin 64 GB, `P3701-0005`
- Carrier: NVIDIA reference carrier, `P3737-0000`
- Architecture/SoC: AArch64, Tegra 234
- Installed memory reported by Linux: 64,336,088 KiB

The correct NVIDIA board configuration remains `jetson-agx-orin-devkit`.

## Current software and boot

- Jetson Linux: R36.5.0
- Distribution: Ubuntu 22.04.5
- Kernel: 5.15.185-tegra with NVIDIA out-of-tree modules
- Root filesystem: ext4 on eMMC `/dev/mmcblk0p1`
- EFI system partition: eMMC `/dev/mmcblk0p10`
- Secure Boot: disabled; firmware setup mode reported
- UEFI `SecureBoot` variable: `0`, read directly from efivarfs on 2026-09-01
- GPU modules loaded: `nvgpu`, `nvidia`, `nvidia_modeset`, `nvidia_drm`

The machine is still dependent on eMMC for its root filesystem and ESP. Moving
the root to NVMe does not by itself prove that the eMMC can be ignored during
boot. Recovery and QSPI/UEFI behavior must be established first.

## Storage

### NVMe

- Device: `/dev/nvme0n1`
- Model: Kingston KC3000 2 TB
- Reported capacity: 2,048,408,248,320 bytes
- Current filesystem: ext4
- Current mount point: `/storage`
- SMART critical warning: 0
- Available spare: 100%
- Percentage used: 0%
- Media errors: 0
- Unsafe shutdowns: 50
- Error-log entries: 45
- Composite temperature: 54°C; secondary sensor: 71°C

This conflicts with the initial description of a 1 TB target. The actual device
was authorized for complete erasure by the user on 2026-09-01 after confirming
that its contents were backed up or no longer required. That authorization is
specific to the observed Kingston 2 TB NVMe and does not authorize eMMC erasure
or firmware mutation. The SMART report shows no wear or media-error concern;
temperature should be monitored under sustained build and inference workloads.

### eMMC

- Device: `/dev/mmcblk0`, approximately 63.6 GB
- Manufacture date: 2024-03
- `pre_eol_info`: `0x01` (normal)
- lifetime estimates A/B: `0x01 0x01` (0–10% consumed)

These health fields do not support a wear-exhaustion diagnosis. The current
boot's kernel journal contained no eMMC, ext4, I/O, timeout, or storage-reset
event; the only filtered line was an unrelated Bluetooth HCI reset. This does
not exclude intermittent or historical faults, so eMMC remains outside the
planned runtime data path without being classified as failed.

## Swap

Eight zram swap devices are active, each 4,117,512,192 bytes, for approximately
32.9 GB total. This validates zram as the existing platform pattern. The Arch
image will begin with zram only and will not use eMMC for swap or cache.

## Boot-slot state

Boot-slot evidence reports R36.5.0, active/current slot B, both slots normal,
and no pending capsule update. These values were reconfirmed over authenticated
SSH on 2026-09-01. The target answered as AArch64 and the SSH transport was
tested with a dedicated LAN key; this is useful for inventory but is not a
substitute for USB Force Recovery.

## Open evidence

1. NVMe error-log detail for the 45 recorded entries, if later symptoms warrant.
2. Reproduction of the successful Force Recovery and external-NVMe flash from
   a fresh build checkout and clean media by following `docs/flash-recovery.md`.
3. Current QSPI/UEFI version detail beyond the boot-slot report.
