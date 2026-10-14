# Native and container dependency policy

## Host boundary

The host operating system is Arch Linux ARM on AArch64. Host applications,
libraries, services and build tools must be installed through signed Arch Linux
ARM repositories or project-owned Pacman packages with pinned source hashes.
Host scripts must not invoke APT, `dpkg`, Ubuntu repositories, Ubuntu service
helpers or Debian maintainer scripts.

NVIDIA's Jetson BSP may contain Debian archives or paths whose publisher-assigned
names include `ubuntu`. Those archives are inert source containers only. A
project PKGBUILD may extract reviewed files from them, but it must not execute a
maintainer script or treat their package metadata as host dependency resolution.
The native AArch64 kernel header directory keeps NVIDIA's original name because
renaming the prepared build tree would obscure provenance.

## Container boundary

Containers are optional workload isolation, not a substitute host OS. R1 permits
minimal Debian, vendor, and application images when all of the following hold:

- the image is AArch64-compatible and pinned by digest in committed deployment
  manifests;
- the container is not privileged and receives only its required devices,
  mounts, ports and capabilities;
- NVIDIA GPU access uses the tested CDI device contract;
- persistent data and network exposure are explicit;
- no Ubuntu image, layer, runtime dependency or package repository is used.

Disposable diagnostic containers may use a fixed non-Ubuntu tag when recording a
digest would add no deployment reproducibility. They must use `--rm`, bounded
network/device access and leave no container behind.

## Enforcement

`tests/dependency-policy.sh` rejects Ubuntu container references, APT or `dpkg`
in host scripts and PKGBUILDs, and unpinned images in committed Compose files.
It deliberately scans deployable source rather than documentation or the
downloaded BSP staging tree, where those terms are necessary to describe the
excluded upstream payload.
