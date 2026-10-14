# Supply-chain policy

## Trust boundary

There is no complete source-only or GitHub-hosted replacement for the Jetson
Linux BSP. The AGX Orin requires NVIDIA firmware and userspace components that
are distributed as binaries. A third-party GitHub bundle would add another
publisher without removing trust in NVIDIA, so this project does not consume
repacked BSP binaries.

Inputs are accepted only from the original publisher and pinned in
`config/inputs.lock.json`:

- Arch Linux ARM rootfs: official artifact plus detached OpenPGP signature.
- NVIDIA BSP: `developer.download.nvidia.com` artifact matching NVIDIA's
  published release digest, plus a locally recorded SHA-256.
- Omarchy: upstream Git commit, to be pinned before desktop integration.
- NVIDIA open components: NVIDIA's release-tagged source archives or official
  source repositories, pinned before compilation.
- NVIDIA Debian packages that are not in the BSP tarball (for example
  `nvidia-l4t-init` and the NVIDIA Container Toolkit): downloaded at build
  time from NVIDIA's official apt repository (`repo.download.nvidia.com`),
  pinned by version and SHA-256 in the package's `PKGBUILD` or `sources.lock`.

This repository never commits NVIDIA binaries. Every NVIDIA component is
downloaded from NVIDIA by the person building the packages and remains under
NVIDIA's licence; `tests/public-hygiene.sh` fails CI if a `.deb`, shared
object, kernel module or other binary blob is committed.

## Verification performed

The 2026-09-01 input capture established:

- Arch rootfs OpenPGP signature is good.
- Signature key fingerprint exactly matches the fingerprint independently
  published on Arch Linux ARM's HTTPS package-signing page.
- NVIDIA BSP SHA-1 exactly matches NVIDIA's R39.2.1 release manifest.
- Local SHA-256 and byte counts are recorded for both archives.
- Archive listings contain no absolute paths or parent-directory traversal.
- Archive listings contain no block, character, pipe, or socket entries.
- The BSP contains `jetson-agx-orin-devkit.conf`, the T234 NVMe flash layout,
  and NVIDIA's initrd-flash documentation.

The official Arch Linux ARM artifact host presented a TLS certificate name
mismatch. TLS verification was not disabled. The artifact and signature were
retrieved using the publisher's documented HTTP endpoint and the payload was
accepted only after detached-signature verification against the separately
published full fingerprint.

## Source-first integration

Where NVIDIA publishes the corresponding release sources, this project will
prefer reproducible builds for:

- Linux kernel
- NVIDIA out-of-tree modules
- NVGPU sources
- NVIDIA display kernel modules
- device trees and open supporting utilities

Vendor binaries remain necessary for firmware, parts of the boot chain, CUDA,
cuDNN, TensorRT, VPI, and portions of graphics/multimedia userspace. Each file
imported from the BSP will be owned by a project package and included in an
inventory; the BSP will not be executed during offline inspection.

## Malware-scanning limitation

ClamAV, YARA, Binwalk, Syft, Grype, and Trivy were not installed on the build
host at capture time. No malware-scan or vulnerability-scan claim is made.
Those tools can add heuristics and inventories, but they cannot prove the
absence of malicious logic in proprietary firmware or binaries. Publisher
provenance, cryptographic verification, minimal binary inclusion, sandboxed
inspection, and bounded runtime validation remain the primary controls.

## R1 release channel

`scripts/build-release-channel.sh` accepts a staged directory containing at
least one AArch64 package and one image or rootfs archive. It rejects symlinked
private keys and invalid compatibility metadata, copies only allowlisted
artifact types, emits deterministic metadata using an explicit
`SOURCE_DATE_EPOCH`, and signs the complete checksum manifest with Ed25519.
The published directory contains the public key, never the private key.

Two builds from identical inputs, epoch and ephemeral test key must be
byte-identical. Both checksum verification and the Ed25519 signature must pass,
and a changed artifact must fail verification. The production signing key must
be supplied from an external secret store; it must not enter Git, CI logs,
process arguments on a shared host, or the release directory. Publishing a
production R1 channel remains blocked until a maintainer creates that key and
stores it outside the repository.
