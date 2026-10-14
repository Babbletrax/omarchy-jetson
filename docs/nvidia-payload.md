# NVIDIA payload integration

## Verified selection

The pinned Jetson Linux 39.2.1 BSP contains both Debian packages and raw TBZ2
payloads. Arch integration will use the raw payloads as packaging inputs; it
will not execute `dpkg`, maintainer scripts, `apply_binaries.sh`, or binaries
from the downloaded BSP during offline assembly.

Jetson AGX Orin uses the NVGPU compute driver. The initial image therefore
selects the `nvgpu` payload variants. The OpenRM variants remain excluded unless
a later hardware test or NVIDIA release requirement proves they are necessary.
JetPack 7.2 permits the display-module variants to coexist, but that does not
change Orin's NVGPU compute-driver selection.

The kernel image identifies itself as `6.8.12-1021-tegra`, and the supplement
archive installs modules under the matching directory. The selected board DTB
is `tegra234-p3737-0000+p3701-0005-nv.dtb`.

## Initial payload groups

| Payload | Purpose | Initial policy |
|---|---|---|
| `kernel/Image` | NVIDIA Jetson boot kernel | Required |
| `kernel/dtb/tegra234-p3737-0000+p3701-0005-nv.dtb` | Production 64 GB module on reference carrier | Required |
| `kernel/kernel_supplements.tbz2` | Kernel modules for the pinned ABI | Required |
| `kernel/kernel_display_supplements.tbz2` | Tegra display support module | Required for desktop milestone |
| `nv_tegra/nvidia_drivers.tbz2` | EGL, GBM, Vulkan, multimedia, services, and firmware integration | Inventory and split into owned packages |
| `nv_tegra/nvidia_l4t_cuda_nvgpu.tbz2` | NVGPU CUDA driver library | Required for CUDA validation |
| `nv_tegra/nvidia_l4t_firmware_nvgpu.tbz2` | NVGPU variant metadata | Required with NVGPU stack |
| `nv_tegra/nvidia_l4t_multimedia_nvgpu.tbz2` | NVGPU V4L2 integration | Deferred until base GPU boot passes |
| `nv_tegra/config.tbz2` | Ubuntu-oriented services and configuration | Do not apply wholesale; audit file by file |
| `nv_tegra/nv_tools.tbz2` | Power, fan, and Jetson diagnostics | Audit and package required tools only |

All selected nested archives have zero absolute paths and zero parent-directory
traversal paths. The outer BSP extraction produced 1,682 filesystem nodes,
matching its 1,682 archive entries, and all required board, NVMe flash, and
initrd-flash configuration files are present.

## Portability boundary

Raw libraries use Debian multiarch locations such as
`/usr/lib/aarch64-linux-gnu/nvidia`. Arch packages must provide explicit loader,
EGL vendor, Vulkan ICD, GBM backend, systemd-unit, udev-rule, and dependency
integration. Ubuntu-specific AppArmor, APT, dpkg, initramfs, OEM setup, and
NetworkManager assumptions are excluded unless independently justified.

The generic Arch `linux-aarch64` package may remain installed for package
dependency continuity, but its kernel and DTBs must never become the selected
Jetson boot artifacts. It will be held from upgrades until a project-owned
replacement package expresses the kernel ownership boundary.

## Initial native packages

- `linux-jetson` owns the versioned kernel image, exact production-module DTB,
  and the complete matching module tree.
- `nvidia-jetson-userspace` owns the NVGPU CUDA driver, Tegra firmware, core
  NVIDIA libraries, loader configuration, linker symlinks, and Orin modprobe
  policy.

`nvidia-jetson-userspace` additionally takes NVIDIA's `nvidia-l4t-init`
Debian package for the matching L4T release from NVIDIA's apt repository
(`repo.download.nvidia.com/jetson/`), pinned by SHA-256, and extracts only
the files it needs with `bsdtar`. `nvidia-container-toolkit` fetches the
toolkit 1.19.1 packages the same way. No NVIDIA archive or package is
committed to this repository.

The userspace package deliberately excludes NVIDIA's Ubuntu initramfs updater,
Vulkan-SC development tree, Xorg module, SIPL driver tree, and camera tuning
payload from the console/AI base. Desktop and camera packages can add reviewed
subsets later. Both initial packages have no install script and do not execute
target code while being built.
