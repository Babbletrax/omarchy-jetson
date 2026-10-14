#!/usr/bin/env python3
"""Report and re-pin the third-party upstreams this build vendors.

Every package here pins an upstream by tag or commit and, in several cases,
patches it at build time. Vendoring without an update path is how a build ends
up frozen on a stale commit, so this reports drift and can re-pin one package
at a time.

  check                 what is pinned, what upstream has, what is behind
  update <package>      re-pin to the newest upstream and refresh checksums

Re-pinning deliberately stops short of validating the patches: the guards that
protect them live in the PKGBUILD and fire during `makepkg`, which is the only
place they can be checked honestly. `update` says so and leaves the build to
prove it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PACKAGES = REPO_ROOT / "packages"
API = "https://api.github.com"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def github(path: str) -> object | None:
    request = urllib.request.Request(
        f"{API}{path}",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "omarchy-jetson"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None


class Pin:
    def __init__(self, pkgbuild: Path) -> None:
        self.pkgbuild = pkgbuild
        self.name = pkgbuild.parent.name
        text = read(pkgbuild)
        self.text = text
        repo = re.search(r"https://github\.com/([^/]+)/([^/'\"\s)]+)", text)
        self.owner, self.repo = (repo.group(1), repo.group(2)) if repo else (None, None)
        commit = re.search(r"^_commit=['\"]?([0-9a-f]{7,40})", text, re.M)
        self.commit = commit.group(1) if commit else None
        version = re.search(r"^pkgver=(.+)$", text, re.M)
        self.version = version.group(1).strip() if version else None
        # A package that only repackages a pinned upstream release tracks tags;
        # one pinned to a commit tracks the default branch instead.
        self.tracks = "commit" if self.commit else "release"

    @property
    def pinned(self) -> str:
        return self.commit[:12] if self.commit else (self.version or "?")

    def latest(self) -> tuple[str | None, str | None]:
        """Return (identifier, human label) for the newest upstream."""
        if not self.owner:
            return None, None
        if self.tracks == "commit":
            data = github(f"/repos/{self.owner}/{self.repo}/commits?per_page=1")
            if isinstance(data, list) and data:
                sha = data[0]["sha"]
                when = data[0]["commit"]["committer"]["date"][:10]
                return sha, f"{sha[:12]} ({when})"
            return None, None
        data = github(f"/repos/{self.owner}/{self.repo}/releases/latest")
        if isinstance(data, dict) and data.get("tag_name"):
            tag = data["tag_name"]
            return tag, f"{tag} ({data.get('published_at', '')[:10]})"
        tags = github(f"/repos/{self.owner}/{self.repo}/tags?per_page=1")
        if isinstance(tags, list) and tags:
            return tags[0]["name"], tags[0]["name"]
        return None, None

    @staticmethod
    def _parts(value: str) -> tuple[int, ...]:
        return tuple(int(p) for p in re.findall(r"\d+", value))

    def state(self, latest: str | None) -> str:
        """current, behind, ahead or unknown.

        Ordering matters, not mere inequality: a package pinned to a tag newer
        than the one GitHub calls "latest" is ahead, not behind, and reporting
        that as behind would invite a downgrade.
        """
        if latest is None:
            return "unknown"
        if self.tracks == "commit":
            return "current" if latest.startswith(self.commit or "\0") else "behind"
        mine, theirs = self._parts(self.version or ""), self._parts(latest.lstrip("v"))
        if not mine or not theirs:
            return "current" if latest.lstrip("v") == (self.version or "") else "behind"
        if mine == theirs:
            return "current"
        return "behind" if mine < theirs else "ahead"


def discover() -> list[Pin]:
    pins = []
    for pkgbuild in sorted(PACKAGES.glob("*/PKGBUILD")):
        if "github.com" not in read(pkgbuild):
            continue
        pin = Pin(pkgbuild)
        if pin.owner:
            pins.append(pin)
    return pins


def command_check(args: argparse.Namespace) -> int:
    pins = discover()
    behind = []
    print(f"{'package':<34} {'pinned':<24} {'upstream':<26} state")
    print("-" * 96)
    for pin in pins:
        latest, label = pin.latest()
        state = pin.state(latest)
        if state == "behind":
            behind.append(pin.name)
        shown = {"unknown": "unreachable", "behind": "BEHIND",
                 "ahead": "ahead of latest release"}.get(state, state)
        print(f"{pin.name:<34} {pin.pinned:<24} {(label or '?'):<26} {shown}")
    print()
    if behind:
        print(f"{len(behind)} behind: {', '.join(behind)}")
        print("Re-pin one with:  scripts/check-upstreams.py update <package>")
    else:
        print("all pinned upstreams are current")
    # Drift is information, not failure; --strict makes it a CI signal.
    return 1 if (behind and args.strict) else 0


def sha256_of_url(url: str) -> str | None:
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            digest = hashlib.sha256()
            for chunk in iter(lambda: response.read(1 << 20), b""):
                digest.update(chunk)
            return digest.hexdigest()
    except (urllib.error.URLError, TimeoutError):
        return None


def command_update(args: argparse.Namespace) -> int:
    pins = {pin.name: pin for pin in discover()}
    pin = pins.get(args.package)
    if pin is None:
        print(f"unknown package: {args.package}", file=sys.stderr)
        print(f"known: {', '.join(sorted(pins))}", file=sys.stderr)
        return 2

    latest, label = pin.latest()
    if latest is None:
        print(f"could not reach upstream for {pin.name}", file=sys.stderr)
        return 1
    state = pin.state(latest)
    if state == "current":
        print(f"{pin.name} is already current ({pin.pinned})")
        return 0
    if state == "ahead":
        print(f"{pin.name} is pinned at {pin.pinned}, ahead of upstream's latest "
              f"release ({label}). Refusing to downgrade.", file=sys.stderr)
        return 1

    text = pin.text
    if pin.tracks == "commit":
        text = re.sub(r"(^_commit=['\"]?)[0-9a-f]{7,40}", rf"\g<1>{latest}", text, count=1, flags=re.M)
        url = f"https://github.com/{pin.owner}/{pin.repo}/archive/{latest}.tar.gz"
    else:
        new_version = latest.lstrip("v")
        text = re.sub(r"^pkgver=.+$", f"pkgver={new_version}", text, count=1, flags=re.M)
        url = f"https://github.com/{pin.owner}/{pin.repo}/archive/refs/tags/{latest}.tar.gz"

    print(f"{pin.name}: {pin.pinned} -> {label}")
    print(f"fetching {url}")
    digest = sha256_of_url(url)
    if digest is None:
        print("could not download the new archive; nothing written", file=sys.stderr)
        return 1

    # Only the first checksum is the upstream archive; the rest are local files
    # that this must not disturb.
    sums = re.search(r"sha256sums=\((.*?)\n\)", text, re.S)
    if sums:
        entries = [line.strip().strip("'\"") for line in sums.group(1).strip().splitlines() if line.strip()]
        if entries and entries[0] != "SKIP":
            entries[0] = digest
            block = "sha256sums=(\n" + "".join(f"  '{e}'\n" for e in entries) + ")"
            text = re.sub(r"sha256sums=\(.*?\n\)", block, text, count=1, flags=re.S)

    text = re.sub(r"^pkgrel=\d+$", "pkgrel=1", text, count=1, flags=re.M)
    pin.pkgbuild.write_text(text, encoding="utf-8")
    print(f"wrote {pin.pkgbuild.relative_to(REPO_ROOT)} (pkgrel reset to 1)")
    print()
    print("Not yet verified. Any patch this package applies to the upstream tree")
    print("is guarded inside package(), and only a build can tell you whether the")
    print("guards still match:")
    print(f"    (cd packages/{pin.name} && makepkg -f --noconfirm)")
    print("A guard that no longer matches fails the build by design -- that is the")
    print("signal that upstream moved the code a patch depends on.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command")
    check = sub.add_parser("check", help="report pinned versus upstream")
    check.add_argument("--strict", action="store_true",
                       help="exit non-zero when anything is behind (for CI)")
    update = sub.add_parser("update", help="re-pin one package to the newest upstream")
    update.add_argument("package")
    args = parser.parse_args()
    if args.command == "update":
        return command_update(args)
    if args.command is None:
        args.strict = False
    return command_check(args)


if __name__ == "__main__":
    sys.exit(main())
