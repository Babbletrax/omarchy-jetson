# Evidence and execution gates

No image construction or flashing may begin until the relevant gate is
recorded as passing.

## Gate A: target identity

- module identifier and SKU
- carrier-board identifier
- Jetson Linux release and current kernel
- QSPI/UEFI version and boot entries
- Secure Boot/fuse status where readable without mutation
- NVMe model, serial, namespace, size, firmware, and SMART health
- eMMC health evidence and current boot dependency

The 2026-09-01 inventory confirms the module, carrier, BSP, boot dependency,
block topology, NVMe SMART health, `/storage` data disposition and erase
authorization, current eMMC kernel error evidence, disabled UEFI Secure Boot,
and healthy A/B bootloader-slot state. Low-level fuse interpretation and a
proven USB Force Recovery path remain open; the recovery proof is mandatory
before target mutation.

## Gate B: host capability

- supported x86_64 or AArch64 Linux build host
- sufficient free disk space (at least 150 GiB recommended)
- USB recovery connectivity
- required archive, signing, filesystem, and cross-architecture tools
- a second copy of recovery artifacts outside the target

## Gate C: immutable inputs

- exact NVIDIA BSP URL and SHA-256 digest
- exact Arch rootfs snapshot URL, signature, and signing key
- exact Omarchy commit
- accepted licenses recorded without redistributing restricted artifacts

The Arch `latest` URL is discovery-only. A build must resolve it to immutable
content and record its digest before extraction.

## Gate D: rootfs construction

- rootfs extracted with ownership, ACLs, capabilities, and extended attributes
- Arch kernel package excluded or prevented from becoming the boot default
- NVIDIA files installed through owned packages
- no runtime dependency on the eMMC under investigation
- rootfs passes offline structural checks

Gate D passed in the disposable integration tree on 2026-09-01. All three
project packages are registered in Pacman with zero missing files; the selected
kernel, initrd, module ABI, production-module DTB, NVGPU CUDA path, firmware
links, account locks, and first-boot identity state passed offline checks. This
does not constitute a hardware boot result.

## Gate E: non-destructive boot test

- boot configuration targets the staged NVMe root
- recovery path is proven before changing boot order
- first boot is console/headless
- SSH host keys and machine identity are generated on first boot
- default Arch Linux ARM passwords are disabled before network exposure

## Gate F: bounded hardware validation

- NVMe root mounted and eMMC unused
- Ethernet, Wi-Fi, and Bluetooth as required
- GPU modules and device nodes present
- CUDA known-answer test
- EGL, GBM, Vulkan, and hardware video capability probes
- Docker GPU smoke test

Only after Gate F passes may the graphical desktop be added.
