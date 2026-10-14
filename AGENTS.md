# Contributor and coding-agent guide

This file covers how to work in this repository. It applies to human
contributors and to AI coding agents alike. Read [README.md](README.md) first
for what the project is.

## Read before changing anything

1. [docs/delivery-checklist.md](docs/delivery-checklist.md) is the work queue
   and holds the acceptance wording.
2. [docs/review.md](docs/review.md) records prior attempts, failures and
   verified hardware evidence.
3. Read [docs/architecture.md](docs/architecture.md),
   [docs/dependency-policy.md](docs/dependency-policy.md) and
   [docs/supply-chain.md](docs/supply-chain.md) for the platform and
   dependency constraints.
4. Read the existing package, config and test you are about to touch before
   writing new code.

## Platform invariants

- The target is the Jetson AGX Orin (64 GB tested), AArch64, running Arch Linux
  ARM from NVMe.
- The NVIDIA boundary is Jetson Linux 39.2.1 / JetPack 7.2.1 with kernel
  `6.8.12-1021-tegra`.
- **Kernel safety.**
  - Never replace NVIDIA's boot firmware, kernel, DTB, modules, initrd, GPU or
    CUDA components with generic Arch packages.
  - Keep the generic kernel held with
    `IgnorePkg = linux-aarch64 linux-aarch64-headers`.
  - Changes to the kernel, boot chain or flashing need explicit review and
    evidence from real hardware.
- Do not use eMMC for routine storage, cache or swap. Swap is zram.
- Do not add an Ubuntu host dependency or an implicit Ubuntu workload image.
- Never commit NVIDIA binaries or other vendored packages. PKGBUILDs download
  them from the publisher's official URL and pin each one with `sha256sums`.
- Keep services loopback-only unless a reviewed change requires otherwise.
- Never put credentials, tokens, private keys, internal hostnames, private IP
  addresses or personal data in source, logs, tests or fixtures.
  `tests/public-hygiene.sh` enforces this.

## Upstream alignment

This project is a thin layer over **stock upstream Omarchy**, not a fork.

- Prefer upstream's packages, commands, themes, menus and keybindings. Override
  only where Jetson hardware forces a difference.
- Overrides belong in `/usr/lib/omarchy-jetson/bin`, which comes first on
  `PATH` through `packages/omarchy-jetson-upstream`. Never overwrite files that
  upstream owns in `/usr/bin` or `/usr/share/omarchy`.
- Add menu entries through upstream's extension point. To do that, edit
  `packages/omarchy-jetson-upstream/menu-additions.jsonc`, then regenerate
  `default-menu-extension.jsonc` with `scripts/generate-menu-extension.py`.
  Never hand-edit the generated file.
- Mark temporary workarounds, such as the Qt 6.12 shell-fix hook, as temporary,
  and make each one a no-op once upstream ships the fix.
- Do not rebind upstream shortcuts. See
  [docs/shortcut-contract.md](docs/shortcut-contract.md).
- Users update with `omarchy-update`.

## Versions and pinning

- Avoid pinning versions where a signed rolling repository already provides
  the package, for example Arch Linux ARM or upstream Omarchy's `[omarchy]`
  repository.
- Pin what is not covered that way by version and SHA-256: NVIDIA payloads,
  release tarballs and anything built here. Verify publisher signatures where
  they exist.
- Establish the versions actually installed on the target before you implement
  anything version-sensitive.
- When a package's contents change, bump its `pkgrel`.

## Checks

```sh
make check
```

- `make check` needs `bash`, `jq`, `ripgrep`, `python3` and ShellCheck 0.11.0
  on `PATH`. The static test skips ShellCheck with a warning if ShellCheck is
  missing, so check that `shellcheck --version` works before trusting a local
  pass.
- CI (`.github/workflows/`) runs the same checks on an arm64 runner, along
  with the public-hygiene scan and gitleaks.
- `make check` validates the repository. It does not prove that a change works
  on the hardware. For a target-runtime item, record a result from a real Orin
  in `docs/review.md` before you check the item off.

## Change discipline

- Repair the smallest verified mismatch and keep work that is known to be good.
- Build packages natively on AArch64.
- Run a narrow fixture test before any live or privileged execution.
- Destructive and flashing commands are confined to guarded scripts.
  `tests/static.sh` checks this.
- Check correctness, compatibility with upstream, safety, maintainability and
  testability before you open a pull request.
