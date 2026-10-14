# Contributing

Thanks for helping. This is an unofficial community port, so please keep
reports and patches about the Jetson port here, not with the Omarchy or NVIDIA
projects.

## Before you start

- Read [README.md](README.md) and [AGENTS.md](AGENTS.md). AGENTS.md holds the
  engineering rules for both humans and coding agents.
- For anything larger than a small fix, open an issue first to discuss the
  approach.
- Hardware-affecting changes are risky. A mistake can leave a board unbootable
  until it is re-flashed. This covers the kernel, initrd, DTB, NVIDIA packages,
  flashing scripts and power modes.

## Making a change

1. Keep the Jetson layer thin. Prefer upstream Omarchy behaviour, and override
   only what the hardware requires.
2. Bump `pkgrel` in every PKGBUILD whose packaged contents change, and update
   its `sha256sums`.
3. Never commit binaries (`.deb`, `.so`, `.ko`, package archives, firmware).
   Point the PKGBUILD at the publisher's official download URL and pin the
   checksum.
4. Don't include internal hostnames, private IP addresses, e-mail addresses,
   credentials or other personal data. Use `192.0.2.0/24` and `example.com` in
   examples.
5. Run the checks:

   ```sh
   make check
   ```

   You need `bash`, `jq`, `ripgrep`, `python3` and ShellCheck 0.11.0.
6. For changes that only matter on the device, say in the pull request what you
   tested on real hardware: module, JetPack version and commands run. Add the
   evidence to `docs/review.md` when it closes a checklist item.

## Pull requests

- Keep each pull request to one topic and explain why the change is needed.
- CI must pass: `checks`, `public hygiene` and `secrets`.
- By contributing, you agree that your contribution is licensed under the
  [MIT License](LICENSE).

## Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
