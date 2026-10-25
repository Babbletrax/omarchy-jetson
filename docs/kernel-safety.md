# Kernel safety: the last-good kernel

`omarchy-jetson-kernel-safety` keeps a copy of the kernel that is running now
and a `last-good` entry in the boot menu, so that a kernel or Jetson BSP update
that does not boot can be undone from the boot menu instead of by
re-flashing. It takes the backup only. Nothing restores automatically yet; you
pick `last-good` by hand.

Status: fixture-tested only. It has not run on a real Orin yet. See
[Before first use on a board](#before-first-use-on-a-board).

## How the board boots

UEFI starts NVIDIA's L4TLauncher, which reads `/boot/extlinux/extlinux.conf` on
the NVMe root filesystem. There is no separate `/boot` partition. The `DEFAULT`
entry (`original`) boots `/boot/Image`, a symlink to `Image-<version>` from
`linux-jetson`, with `/boot/initrd`, NVIDIA's initrd from
`linux-jetson-initrd`. The entries have no `FDT` line, so the firmware supplies
the device tree from the flashed partitions. The kernel then loads its modules,
including NVIDIA's out-of-tree modules under `updates/`, from
`/usr/lib/modules/<version>`.

## What happens on a kernel update

A pacman hook, `10-omarchy-jetson-kernel-backup.hook`, runs
`omarchy-jetson-kernel backup` before any transaction that installs, upgrades
or removes `linux-jetson`, `linux-jetson-initrd`, any `nvidia-jetson-*` package
or `linux-aarch64` (which owns the `/boot/Image` symlink and must stay held by
`IgnorePkg`). `linux-jetson-headers` is not a trigger, because headers play no
part in booting and always update together with `linux-jetson`.

1. It confirms that the running kernel (`uname -r`) is the installed one: the
   `DEFAULT` entry's kernel resolves to `/boot/Image-<version>`, which
   `linux-jetson` owns, its module tree exists, and neither the kernel, the
   initrd nor any module changed after this boot started. A kernel that has
   not booted yet never becomes last-good.
2. It checks for enough free space: the size of the set plus 64 MiB.
3. It copies the kernel, the initrd, the `FDT` file if the `DEFAULT` entry
   has one, and the whole `/usr/lib/modules/<version>` tree into
   `/boot/last-good.tmp`. It writes `VERSION`, `MANIFEST` (the source paths,
   the `APPEND` line and the installed `linux-jetson*` and `nvidia-jetson-*`
   versions) and `SHA256SUMS`, then checks the copy against the sums.
4. It swaps the copy into `/boot/last-good` in one atomic rename exchange, so
   `/boot/last-good` always holds a complete set.
5. It writes or updates the managed boot entry at the end of `extlinux.conf`:

   ```text
   # >>> omarchy-jetson last-good (managed by omarchy-jetson-kernel; do not edit) >>>
   LABEL last-good
         MENU LABEL last-good: previous working kernel 6.8.12-1021-tegra
         LINUX /boot/last-good/Image
         INITRD /boot/last-good/initrd
         APPEND <the DEFAULT entry's APPEND line> omarchy_jetson.last_good=1
   # <<< omarchy-jetson last-good <<<
   ```

   `DEFAULT` and every other entry stay byte-identical. The previous file is
   kept as `extlinux.conf.omarchy-jetson-<time>.bak`, with the five newest
   kept. If the file is already right, it is not rewritten.

If the set is already current, nothing is copied. If the running kernel is not
the installed one (for example, a reboot after an earlier kernel update is
still pending), the existing last-good is kept and the update goes ahead.

The hook stops the whole update (pacman's `AbortOnFail`) when:

- there is too little free space;
- the copy fails or does not match;
- `extlinux.conf` cannot be parsed. The file must have exactly one `DEFAULT`,
  unique labels, only known directives, Unix line endings, and a `DEFAULT`
  entry with one absolute `LINUX`, `INITRD` and `APPEND`, at most one `FDT` and
  no `FDTDIR` or `OVERLAYS`. The file is then left untouched;
- no last-good exists and the running kernel cannot be saved. To go ahead
  unprotected once, run `sudo omarchy-jetson-kernel allow-unprotected`;
- you are running last-good with its modules mounted (see below). Run
  `sudo omarchy-jetson-kernel release-modules` first.

Booted from `last-good` itself, the hook keeps `/boot/last-good` as it is.

Only one last-good set is kept, about 190 MiB for the current kernel.

## Booting the last-good kernel

If a new kernel does not come up:

1. Power-cycle the board.
2. Watch the boot menu. L4TLauncher prints its boot options, the
   `extlinux.conf` labels, on the serial console (the debug USB port,
   115200 baud) and on the UEFI display. The menu waits `TIMEOUT` tenths
   of a second, 5 seconds here.
3. Choose `last-good: previous working kernel <version>`.

`omarchy-jetson-kernel-modules.service` runs early in that boot, before
`systemd-udevd`, and only when the kernel command line has
`omarchy_jetson.last_good=1`. It mounts `/boot/last-good/modules/<version>`
read-only over `/usr/lib/modules/<version>`, creating the directory if pacman
removed it. The old kernel then loads its own modules even when the new
package replaced the tree under the same version string.

Then check the state and decide:

```sh
omarchy-jetson-kernel status
sudo omarchy-jetson-kernel verify
```

To go back to the old kernel for good, release the modules and reinstall the
previous packages from the cache, for example:

```sh
sudo omarchy-jetson-kernel release-modules
sudo pacman -U /var/cache/pacman/pkg/linux-jetson-<old>.pkg.tar.zst \
  /var/cache/pacman/pkg/linux-jetson-initrd-<old>.pkg.tar.zst
```

`DEFAULT` was never changed, so a plain reboot starts the installed kernel
again.

If the menu cannot be reached, boot trusted recovery media as described in
[recovery.md](recovery.md), mount the NVMe root, and copy the files from
`last-good` back by hand, or set `DEFAULT last-good` in its `extlinux.conf`
(keep a copy of the file). The last resort is
re-flashing ([flash-recovery.md](flash-recovery.md)).

## What is not protected

- **No automatic restore.** A kernel that hangs or panics stays on screen
  until someone picks `last-good`.
- **Power loss during the update.** The backup is complete before pacman
  starts, but pacman's own writes to `/boot` and `/usr/lib/modules` are not
  atomic. A cut mid-transaction can leave the installed kernel half-written;
  `last-good` is still intact.
- **The device tree and boot firmware.** With no `FDT` line, the DTB comes from
  the flashed QSPI and boot partitions, as do UEFI and L4TLauncher. A BSP
  update that needs new firmware is outside this tool and still means
  following [flash-recovery.md](flash-recovery.md).
- **Userspace that must match the kernel.** The NVIDIA userspace
  (`nvidia-jetson-userspace`, CUDA) and firmware in `/usr/lib/firmware` and
  `/etc/firmware` are not saved. The last-good kernel can boot with newer
  userspace whose GPU or CUDA parts do not match.
- **A kernel that boots but is subtly broken.** It becomes last-good at the
  next kernel update. Keep a separate snapshot (`omarchy-jetson-snapshot`)
  before big changes.
- **Automatic updates.** Kernel and BSP updates still never install by
  themselves (`omarchy-jetson-updates`). The backup protects the update you
  run by hand.

## Future work: a one-shot trial boot

The next step is the Pi build's design adapted to UEFI: after a kernel update,
the board keeps booting last-good by default and tries the new kernel for one
boot only, for example through UEFI `BootNext` or an L4TLauncher one-shot
`DEFAULT` override. It then promotes the new kernel only after a health check
passes (login screen reached, no failed units, GPU present), and otherwise falls
back by itself. That needs a reliable way to detect a failed boot (a panic or
hang reboot, a watchdog, a boot counter), and evidence on real hardware. It is
not implemented.

## Before first use on a board

This has to be done with someone at the board, with serial console access and
recovery media ready:

1. Install the package and run `sudo omarchy-jetson-kernel backup` by hand.
   Compare `extlinux.conf` with its `.bak` copy.
2. Reboot and confirm that the L4TLauncher menu shows `last-good` on the serial
   console and on HDMI, and that `DEFAULT` still boots by itself.
3. Boot `last-good` from the menu. Check `uname -r`, that `/proc/cmdline` has
   the marker, that the module mount is active, that `systemctl --failed` is
   empty, and the GPU and CUDA checks in [gates.md](gates.md).
4. Rehearse a real kernel update (for example a `pkgrel` rebuild of
   `linux-jetson`) and the fallback, then record the results in
   [review.md](review.md).
