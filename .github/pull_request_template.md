## What and why

<!-- One topic per pull request. What does this change, and why is it needed? -->

## Tests

<!--
A change to functional code (packages/, scripts/, ci/, config/, any *.sh, *.py
or executable, PKGBUILD logic) must add or change a test under tests/ and
register it in the Makefile; the "tests required" check enforces this.
Docs-only, workflow-only and pkgver/pkgrel/checksum-only bumps are exempt.
If no test can cover the change, say why; a maintainer may apply the
`no-tests-needed` label.
-->

- [ ] `make check` passes locally (with ShellCheck 0.11.0 on `PATH`)
- [ ] Added or changed tests: <!-- which file(s) in tests/ -->
- [ ] `pkgrel` bumped and `sha256sums` updated for every package whose contents changed

## Hardware evidence

<!--
For changes that only matter on the device: module, JetPack version, and the
commands you ran on a real Jetson AGX Orin. Write "n/a" for repository-only
changes.
-->

## Checklist

- [ ] No credentials, internal hostnames, private IP addresses, personal paths or e-mail addresses (use `192.0.2.0/24` and `example.com` in examples)
- [ ] No committed binaries; downloads are pinned by checksum from the publisher's official URL
