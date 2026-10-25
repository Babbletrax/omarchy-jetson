#!/usr/bin/env python3
"""Known vulnerabilities in what the omarchy-jetson build ships.

1. Repository packages: the workstation package list plus the dependencies of
   every package in packages/, resolved to the full install closure with
   `pacman -Sp` (repo versions, nothing installed), checked against the Arch
   Linux security tracker.
2. Vendored upstreams pinned in a PKGBUILD that OSV tracks, checked by version.

Fails on a HIGH/CRITICAL issue the shipped version is affected by when a fixed
version exists; unfixed or lower-severity issues are reported as warnings.
Run as root (or with sudo for pacman) after `pacman -Sy`.
"""

import json
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TRACKER = "https://security.archlinux.org/issues/all.json"
OSV = "https://api.osv.dev/v1/query"
# packages/<dir> -> OSV package for its pinned upstream.
OSV_PINS = {
    "nvidia-container-toolkit": ("Go", "github.com/NVIDIA/nvidia-container-toolkit"),
}
SERIOUS = {"High", "Critical"}


def fetch_json(url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def pkgbuild_vars(pkgbuild, *names):
    script = 'export JETSON_BSP_DIR=/nonexistent JETSON_INITRD=/nonexistent; source "$1" >/dev/null 2>&1; ' + "; ".join(
        f'printf "%s\\0" "${{{n}[@]}}"; printf "\\1"' for n in names
    )
    out = subprocess.run(["bash", "-c", script, "_", str(pkgbuild)], capture_output=True, text=True).stdout
    parts = out.split("\1")[: len(names)]
    parts += [""] * (len(names) - len(parts))
    return [[v for v in part.split("\0") if v] for part in parts]


def strip_ver(dep):
    for op in (">=", "<=", "=", ">", "<"):
        dep = dep.split(op)[0]
    return dep.strip()


def vercmp(a, b):
    return int(subprocess.run(["vercmp", a, b], capture_output=True, text=True).stdout.strip())


def main():
    wanted = set()
    for line in (REPO / "config/workstation-packages.txt").read_text().splitlines():
        line = line.split("#")[0].strip()
        if line:
            wanted.add(line)
    own = set()
    for pkgbuild in sorted(REPO.glob("packages/*/PKGBUILD")):
        names, deps, mdeps = pkgbuild_vars(pkgbuild, "pkgname", "depends", "makedepends")
        own.update(names)
        wanted.update(strip_ver(d) for d in deps)
    wanted -= own

    in_repo = [
        p
        for p in sorted(wanted)
        if subprocess.run(["pacman", "-Sp", "--print-format", "%n", p], capture_output=True).returncode == 0
    ]
    missing = sorted(wanted - set(in_repo))
    closure = {}
    out = subprocess.run(
        ["pacman", "-Sp", "--print-format", "%n %v", *in_repo], capture_output=True, text=True, check=True
    ).stdout
    for line in out.splitlines():
        name, ver = line.split()
        closure[name] = ver
    print(
        f"{len(closure)} repository packages in the install closure"
        + (f"; not in the repos (AUR/own, not checked): {', '.join(missing)}" if missing else "")
    )

    failures, warnings = [], []
    for avg in fetch_json(TRACKER):
        if avg["status"] in ("Not affected",):
            continue
        for pkg in avg["packages"]:
            ver = closure.get(pkg)
            if not ver:
                continue
            fixed = avg.get("fixed")
            if fixed and vercmp(ver, fixed) >= 0:
                continue
            if avg.get("affected") and vercmp(ver, avg["affected"]) < 0 and not fixed:
                continue
            msg = (
                f"{pkg} {ver}: {avg['name']} {avg['severity']} {avg['type']} "
                f"({', '.join(avg['issues'][:4])}{'...' if len(avg['issues']) > 4 else ''})"
                + (f", fixed in {fixed}" if fixed else ", no fix yet")
            )
            (failures if fixed and avg["severity"] in SERIOUS else warnings).append(msg)

    for pkg_dir, (eco, osv_name) in OSV_PINS.items():
        (ver,) = pkgbuild_vars(REPO / "packages" / pkg_dir / "PKGBUILD", "pkgver")
        if not ver:
            continue
        res = fetch_json(OSV, {"package": {"ecosystem": eco, "name": osv_name}, "version": ver[0]})
        for vuln in res.get("vulns", []):
            sev = (vuln.get("database_specific") or {}).get("severity", "UNKNOWN").title()
            msg = f"{pkg_dir} {ver[0]}: {vuln['id']} {sev} {vuln.get('summary', '')[:90]}"
            (failures if sev in SERIOUS else warnings).append(msg)

    for m in warnings:
        print("WARN ", m)
    for m in failures:
        print("FAIL ", m)
    print(f"{len(failures)} failing, {len(warnings)} warnings")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
