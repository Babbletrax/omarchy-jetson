# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report them privately through GitHub's private vulnerability reporting. Go to
the repository's **Security** tab and choose **Report a vulnerability**. The
report opens a private security advisory that only the maintainers can see.

Private vulnerability reporting must be enabled for the repository
(**Settings → Code security → Private vulnerability reporting**). If the
button is missing, contact a maintainer listed in `.github/CODEOWNERS` and ask
for a private channel without including any details.

Please include:

- the affected package, script or configuration, and the version or commit;
- how to reproduce the problem and what impact you expect;
- any suggested fix.

We aim to acknowledge a report within a week. We will coordinate a fix and a
disclosure date with you.

## Scope

This policy covers the code and configuration in this repository: the PKGBUILDs,
scripts, the Jetson layer over Omarchy, and CI.

Vulnerabilities in upstream components belong with their publishers:

- NVIDIA Jetson Linux, CUDA and the container toolkit:
  <https://www.nvidia.com/en-us/security/>
- Omarchy, Arch Linux ARM, Hyprland and other upstream projects: report through
  each project's own process.

If you are not sure where an issue belongs, report it here and we will help
route it.

## How the repository is checked

Every change runs the checks described in
[CONTRIBUTING.md](CONTRIBUTING.md#continuous-integration). The security-relevant
ones are:

- **Secrets:** gitleaks over the full git history, and trivy's secret scanner.
- **Hygiene:** `tests/public-hygiene.sh` and `tests/no-hardcoded-config.py`
  reject credentials, 1Password references, internal hostnames, private
  addresses, personal paths and e-mail addresses, unknown servers and committed
  binaries.
- **Supply chain:** NVIDIA payloads, release tarballs and other downloads are
  pinned by SHA-256 in the PKGBUILDs; publisher signatures are verified where
  they exist. CI verifies the Arch Linux ARM rootfs and upstream Omarchy
  packages against signing keys committed in `ci/keys/` and pinned by full
  fingerprint in `config/versions.env`, never keys fetched at run time.
  GitHub Actions are pinned to full commit SHAs (Dependabot proposes updates
  after a seven-day cooldown); zizmor and actionlint audit the workflows, and
  OpenSSF Scorecard reports on the project's practices.
- **Known vulnerabilities:** `ci/advisories.py` checks the packages the build
  installs against the Arch Linux security tracker and pinned upstreams against
  OSV, daily; trivy and dependency review cover what they can detect in the tree.
- **CI isolation:** workflows run only on GitHub-hosted runners, with
  read-only tokens by default and no `pull_request_target`, so a pull request
  from a fork cannot reach secrets or a maintainer's machine.
