# AGX Orin Force Recovery and NVMe flash

This procedure is specific to production AGX Orin 64 GB module `P3701-0005` on
reference carrier `P3737-0000`, board config `jetson-agx-orin-devkit`, and the
pinned Jetson Linux 39.2.1 inputs. It erases the selected external NVMe. It does
not authorize or target eMMC.

NVIDIA's R39.2.1 quick start specifies this Force Recovery sequence for AGX
Orin: power off; hold Force Recovery; press and release Power; then release
Force Recovery. The Linux host must show USB ID `0955:7023` before any flash
command. See NVIDIA's [R39.2.1 Quick Start](https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/IN/QuickStart.html).

## Rebuild preparation

1. Start from a clean project checkout at the intended release commit.
2. Run `make check` and `scripts/check-host.sh`.
3. Verify every immutable input against `config/inputs.lock.json` before
   extraction. Accept NVIDIA's license explicitly; never use a repacked BSP.
4. Assemble the Arch rootfs, build the pinned kernel/userspace/initrd packages,
   and apply all four versioned R39.2.1 patches under `patches/`. Each patch must
   pass a dry-run against the clean NVIDIA source before it is applied.
5. Build the flash package outside any seccomp-restricted sandbox. NVIDIA's host bundle
   contains a legacy 32-bit `mkbootimg`; seccomp may reject its i386 `uname`
   syscall even though the target rootfs and kernel are 64-bit AArch64.

## Recovery and flash gates

1. Connect the host to the AGX Orin recovery USB-C port.
2. Enter Force Recovery using the sequence above and run `lsusb` on the host.
   Stop unless `0955:7023 NVIDIA Corp.` is present.
3. Confirm the module/carrier tuple and external target are exactly the pinned
   values. The target passed to NVIDIA is `nvme0n1p1`; never substitute an
   `mmcblk` device.
4. Use NVIDIA's documented R39.2.1 external-NVMe command shape:

   ```sh
   sudo ./l4t_initrd_flash.sh --external-device nvme0n1p1 \
     -c tools/kernel_flash/flash_l4t_t234_nvme.xml \
     --erase-all jetson-agx-orin-devkit external
   ```

5. Retain complete host logs. Do not interrupt the black-screen phase: the
   target recovery initrd performs USB networking, GPT creation, ext4 format,
   Zstandard rootfs extraction, verification and reboot before display output
   is expected.
6. In UEFI, select the NVMe boot entry if it is not already first.

## Post-flash acceptance

The first successful run erased/wrote QSPI with per-image digest matches,
formatted the 1.999 TB NVMe APP partition, extracted the Arch rootfs, and passed
a read-only five-pass ext4 check. After boot, require all of the following:

```sh
uname -m
findmnt -no SOURCE,FSTYPE /
systemctl --failed --no-pager
systemctl --user --failed --no-pager
```

Expected architecture is `aarch64`; root is `/dev/nvme0n1p1 ext4`; neither
failed-unit query has entries; and no eMMC partition is mounted. Then run the
bounded GPU, CUDA, network and desktop acceptance cases referenced
by `docs/gates.md`. `R1-PLAT-04` remains open until this exact procedure is
repeated from a clean checkout/media and produces the same results.
