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
5. Add or change a test under `tests/` for any change to functional code,
   and register a new test in the `Makefile`. See [Tests](#tests).
6. Run the checks:

   ```sh
   make check
   ```

   You need `bash`, `git`, `gpg`, `jq`, `ripgrep`, `python3` and ShellCheck
   0.11.0, plus upstream Omarchy's files in `/usr/share/omarchy` and its
   `omarchy*` commands in `/usr/bin`. An Omarchy system has them; elsewhere,
   `sudo ci/install-omarchy.sh pinned` unpacks them from the signed package.
7. For changes that only matter on the device, say in the pull request what you
   tested on real hardware: module, JetPack version and commands run. Add the
   evidence to `docs/review.md` when it closes a checklist item.

## Tests

A pull request that changes functional code must add or change something
under `tests/`. Functional code is anything in `packages/`, `scripts/`, `ci/`,
`config/`, `recovery/` or `patches/`, the `Makefile`, and any `*.sh`, `*.py` or
executable file. Exempt: Markdown and `docs/`, `.github/`, Dependabot updates,
and PKGBUILD edits that only bump `pkgver`, `pkgrel` or checksums. The
`tests required` check enforces this (`ci/tests-required.sh`). If no test can
cover a change, explain why in the pull request; a maintainer can apply the
`no-tests-needed` label, and the check records the waiver in its summary.

## Continuous integration

Every pull request runs on GitHub-hosted runners (arm64 where the code is
architecture-specific); nothing runs on a maintainer's own machine. All
actions are pinned to a full commit SHA, tools to a release checksum, and each
job gets only the permissions it needs.

| Workflow | What it checks |
| --- | --- |
| `checks` | `make check` (regression suites, static checks, ShellCheck, public hygiene rules) against the pinned upstream Omarchy release |
| `public hygiene` | `tests/public-hygiene.sh`, including the maintainer's private patterns where the secret is available (not on fork pull requests), and `tests/no-hardcoded-config.py` |
| `lint` | `ruff check`; `shfmt -i 2 -ci` and `ruff format` on the files a change touches; offline check of relative Markdown links |
| `tests required` | functional changes come with tests (see above) |
| `packages` | builds changed packages (all of them on `main` and weekly) with `makepkg` and `namcap` in an Arch Linux ARM container made from the signature-verified official rootfs |
| `security` | trivy (vulnerabilities, secrets, misconfiguration), dependency review, zizmor and actionlint for the workflows |
| `secrets` | gitleaks over the full history |
| `advisories` | Arch security tracker and OSV advisories for what the build ships |
| `codeql`, `scorecard` | CodeQL for the Python code; OpenSSF Scorecard (scheduled) |
| `upstream next` | the same suites against the newest Omarchy release; informational |

The hard-coded configuration scan fails on literal home paths, private, LAN or
public IP addresses outside the documentation ranges, internal domains, e-mail
addresses and URLs to hosts that are not reviewed public upstreams. A true
positive goes into `tests/no-hardcoded-config.allow` with a comment saying why.
`omarchy-jetson` is only the default hostname: no package or update may write
`/etc/hostname` (`tests/hostname-default.sh`).

## Pull requests

- Keep each pull request to one topic and explain why the change is needed.
- CI must pass. The required checks are `make check`, `public-hygiene.sh`,
  `gitleaks`, `lint` and `tests required`; `packages` must pass when it runs.
- By contributing, you agree that your contribution is licensed under the
  [MIT License](LICENSE).

## Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
