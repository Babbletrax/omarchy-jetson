# Omarchy Jetson

An **unofficial community port** of [Omarchy](https://github.com/omacom/omarchy)
to the NVIDIA Jetson AGX Orin. It runs upstream Omarchy 4 on Arch Linux ARM and
boots through NVIDIA's own Jetson Linux firmware, kernel and GPU stack. A thin
Jetson layer sits on top of stock upstream Omarchy.

> **Not affiliated.** This project is not affiliated with, endorsed by, or
> supported by the Omarchy project, Basecamp/37signals, NVIDIA, or Arch Linux
> ARM. "Omarchy", "NVIDIA", "Jetson", "JetPack" and other names are trademarks
> of their respective owners and are used here only to describe compatibility.
> Report bugs in this port here, not upstream.

## Status

This is experimental. It is used daily on one machine, but expect rough edges.
Flashing a Jetson can leave it unbootable until you recover it with NVIDIA's
tools. Read [docs/flash-recovery.md](docs/flash-recovery.md) before you start.

### Supported hardware

| Item | Tested |
|---|---|
| Module | Jetson AGX Orin 64 GB (`P3701-0005`) |
| Carrier | NVIDIA reference carrier `P3737-0000` (AGX Orin Developer Kit) |
| Board config | `jetson-agx-orin-devkit` |
| Root storage | NVMe, ext4. eMMC is not used at runtime |
| Display | DisplayPort (J18), the dev kit's only display output |

Other Orin modules (32 GB, Orin NX/Nano) are untested. They may need a
different board config, DTB and `nvpmodel` table.

### Platform baseline

- Jetson Linux **39.2.1** (JetPack **7.2.1**)
- Kernel `linux-jetson` **6.8.12-1021-tegra** (NVIDIA's kernel, repackaged for pacman)
- NVIDIA userspace for the Orin NVGPU driver, CUDA 13.2
- Arch Linux ARM (generic AArch64) userland
- Upstream Omarchy 4 (`omarchy` + `omarchy-settings`) from upstream's signed
  aarch64 `[omarchy]` repository

## What works

Each of these has been checked on real hardware.

- Booting from NVMe through NVIDIA's firmware, kernel, DTB and initrd
- Native GPU and CUDA, with a known-answer `deviceQuery` test
- The Docker and NVIDIA Container Toolkit CDI spec for Jetson
- Hyprland/UWSM with upstream Omarchy's shell, themes, menus and keybindings
- Screenshots, screen recording, OCR and the colour picker
- Display resolution, scale and placement, with rollback
- Offline dictation with Voxtype
- Notifications, lock and idle
- NVIDIA power modes
- Snapshot and rollback recovery
- zram swap

Open work is tracked in [docs/delivery-checklist.md](docs/delivery-checklist.md).
The main open items are a second clean-media flash reproduction and a signed
package channel.

## How it differs from stock Omarchy

Upstream Omarchy targets x86_64 PCs. On the Jetson the following are different.

- **Kernel.** The NVIDIA Jetson kernel (`linux-jetson`, `linux-jetson-headers`,
  `linux-jetson-initrd`) replaces Arch's. Add
  `IgnorePkg = linux-aarch64 linux-aarch64-headers` to the target's
  `/etc/pacman.conf` to hold the generic kernel. With the hold in place, an
  update cannot replace the board-support kernel.
- **NVIDIA stack.** `nvidia-jetson-userspace`, `nvidia-jetson-cuda` and
  `nvidia-container-toolkit` repackage NVIDIA's Jetson payload. Generic Arch
  NVIDIA packages are not used, and `nvidia-smi` does not apply.
- **Power.** NVIDIA power modes (`nvpmodel`, through `omarchy-jetson-power` and
  *Setup → Jetson Power Mode*) replace `power-profiles-daemon`.
- **Screen recording.** It uses `wf-recorder` instead of `gpu-screen-recorder`,
  which needs `libnvidia-encode`. Jetson does not ship that library.
- **Qt 6.12 shell hook.** A pacman hook re-applies upstream's post-4.0.4 Qt 6.12
  shell fix (upstream commit `51717f1`) only while the installed `omarchy`
  release lacks it. It will be removed once upstream ships a release that
  includes the fix.
- **Display device.** `AQ_DRM_DEVICES` points at the Tegra display controller by
  path, because the numeric `/dev/dri/cardN` changes between boots.
- **Hardware overrides.** Jetson-specific replacements for a few upstream
  commands live in `/usr/lib/omarchy-jetson/bin`, which comes first on `PATH`.
  Upstream's copies in `/usr/bin` are left untouched. The overrides cover the
  terminal launcher, screen recording and the screensaver effect picker.
- **Menu additions.** Jetson entries are added through upstream's menu extension
  point rather than a fork. Those entries are *Style → Scale and fonts*,
  *Style → Display*, the screensaver effect, *Setup → Jetson Power Mode* and
  *Update → Automatic Updates*.
  Upstream entries whose commands are not packaged on AArch64 are hidden
  automatically.
- **Applications.** Upstream's preinstalled x86 application and web-app bundle
  is not reproduced. VS Code (official arm64 build) and the 1Password CLI are
  packaged for AArch64.

## Repository layout

| Path | Contents |
|---|---|
| `packages/` | PKGBUILDs for the kernel, NVIDIA payload and Jetson layer |
| `config/` | Pinned inputs, rootfs configuration and the Jetson agent skill |
| `scripts/` | Host/target checks, rootfs assembly, initrd build, USB writer |
| `patches/` | Small patches to NVIDIA's L4T flashing scripts for an Arch host/rootfs |
| `recovery/` | UART capture and boot debugging aids |
| `docs/` | Architecture, flashing, recovery, supply chain and evidence |
| `tests/` | Fixture tests run by `make check` |

## Installing

There is no one-click image yet. The current path is as follows.

1. Read [docs/architecture.md](docs/architecture.md),
   [docs/supply-chain.md](docs/supply-chain.md) and
   [docs/nvidia-payload.md](docs/nvidia-payload.md).
2. Prepare a Linux host. Run `./scripts/check-host.sh` to check it.
3. Download NVIDIA's Jetson Linux 39.2.1 BSP yourself and accept NVIDIA's
   licence. Then assemble the Arch rootfs with
   `./scripts/assemble-base-rootfs.sh build/arch-rootfs`.
4. Build the packages natively on AArch64 with `makepkg`, using
   `config/makepkg-aarch64.conf`.
5. Put the module in Force Recovery and flash to NVMe as described in
   [docs/flash-recovery.md](docs/flash-recovery.md).
   [docs/recovery.md](docs/recovery.md) covers getting back to a working system.

Every downloaded input is pinned by SHA-256, and signatures are verified where
the publisher provides them.

## Updating

Update with upstream's updater:

```sh
omarchy-update
```

Upstream's guard blocks a plain `pacman -Syu`.

`omarchy-jetson-updates` adds opt-in automatic updates, off by default. A
daily timer (03:00 unless changed) checks against a private copy of the package
database and pre-downloads. When switched on, the updates install once the
board is online and idle, with enough free space and no other update running,
through the system steps of upstream's `omarchy-update`. The board never
reboots by itself, and kernel or Jetson BSP updates (`linux-jetson*`,
`nvidia-jetson-*`) are never applied automatically; a notification asks you to
run them. Change the settings under *Update → Automatic Updates* or with:

```sh
omarchy-jetson-update-settings --show
omarchy-jetson-update-settings --auto on      # or off
omarchy-jetson-update-settings --time 04:30
```

`omarchy-jetson-kernel-safety` saves the running kernel, its initrd and its
module tree to `/boot/last-good` before any kernel or Jetson BSP update, and
keeps a `last-good` entry in the boot menu that starts it. It never changes
the default entry, and it stops the update if it cannot take the backup.
Check it with `omarchy-jetson-kernel status`. There is no automatic restore
yet; see [docs/kernel-safety.md](docs/kernel-safety.md).

> **Kernel caution.** Never install `linux-aarch64` or generic NVIDIA, firmware
> or bootloader packages on a Jetson. Never remove the `IgnorePkg` hold. The
> board boots only with NVIDIA's matching kernel, DTB, modules and initrd. A
> mismatch means re-flashing from Force Recovery.

## Development

```sh
make check
```

`make check` runs the static contract checks and ShellCheck, which must be on
`PATH`. It also runs the fixture tests and `tests/public-hygiene.sh`, which
keeps internal hostnames, private addresses, personal data and committed
binaries out of the repository. GitHub Actions runs the same checks on an arm64
runner, plus a gitleaks secret scan.

Passing `make check` does not show that a change works on the hardware. Changes
to the kernel, boot, GPU or flashing need evidence from a real Orin.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENTS.md](AGENTS.md). Report security issues privately as described in
[SECURITY.md](SECURITY.md). Participation is covered by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

This repository's own code and documentation are MIT licensed. See
[LICENSE](LICENSE).

- NVIDIA components stay under NVIDIA's licences, including the Jetson Linux
  BSP, the L4T userspace and CUDA. This repository does **not** redistribute
  them. PKGBUILDs download them from NVIDIA's official servers at build time and
  verify them by checksum, and you must accept NVIDIA's terms yourself.
- The NVIDIA Container Toolkit is Apache-2.0 and is downloaded the same way.
- Omarchy is MIT licensed by its authors.
- Arch Linux ARM packages keep their respective upstream licences.
