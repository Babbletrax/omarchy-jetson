#!/usr/bin/env python3
"""Fail on configuration that is specific to one machine, network or person.

Scans every tracked text file for:

  home-path      literal /home/<name> or /Users/<name> paths (use $HOME, ~ or a
                 variable; /home/alarm, the stock Arch Linux ARM user, is fine)
  private-ip     RFC 1918, link-local (169.254/16), CGNAT (100.64/10) and IPv6
                 link-local / unique-local addresses
  public-ip      any other IPv4 address outside loopback, the unspecified
                 address, netmasks and the documentation ranges (192.0.2/24,
                 198.51.100/24, 203.0.113/24)
  internal-host  names under .local, .lan, .internal, .home.arpa, .corp,
                 .localdomain, .intranet or an *.int.* zone
  email          e-mail addresses other than example.* and no-reply addresses
  server-url     URLs whose host is not a reviewed public upstream

The default hostname `omarchy-jetson` is allowed (it is the project name);
tests/hostname-default.sh checks it stays only a default.

Reviewed exceptions live in tests/no-hardcoded-config.allow:
  host <domain>   a public host URLs may point at (subdomains included)
  <glob>:<regex>  a line in a file matching <glob> that matches <regex>

  tests/no-hardcoded-config.py              self-test, then scan the repository
  tests/no-hardcoded-config.py --scan DIR   scan DIR only (exit 1 on findings)
"""

from __future__ import annotations

import fnmatch
import ipaddress
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SELF = "tests/no-hardcoded-config.py"
ALLOW = "tests/no-hardcoded-config.allow"

HOME_RE = re.compile(r"(?<![\w$}])/(?:home|Users)/([A-Za-z_][A-Za-z0-9_.-]*)")
STOCK_USERS = {"alarm"}  # Arch Linux ARM's published default account

IPV4_RE = re.compile(r"(?<![\w.:-])((?:\d{1,3}\.){3}\d{1,3})(?:/\d{1,2})?(?![\w-]|\.\d)")
IPV6_RE = re.compile(r"(?<![\w:])((?:fe[89ab][0-9a-f]|f[cd][0-9a-f]{2}):[0-9a-f:]*:[0-9a-f:]*)", re.IGNORECASE)
DOC_NETS = [ipaddress.ip_network(n) for n in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")]
CGNAT = ipaddress.ip_network("100.64.0.0/10")

INTERNAL_TLDS = "local|lan|internal|home\\.arpa|corp|localdomain|intranet"
HOST_RE = re.compile(
    r"(?<![\w.-])((?:[a-z0-9-]+\.)+(?:" + INTERNAL_TLDS + r"))(?![\w-]|\.[a-z0-9])"
    r"|(?<![\w.-])([a-z0-9-]+\.int\.[a-z0-9-]+\.[a-z]{2,})\b",
    re.IGNORECASE,
)

EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})")
SYSTEMD_SUFFIXES = (".service", ".socket", ".timer", ".target", ".path", ".mount", ".slice", ".scope", ".device")
SSH_REMOTES = {"git@github.com", "git@gitlab.com"}

URL_RE = re.compile(r"\b(?:https?|ftps?|wss?|git|ssh|rsync|sftp)://([^/\s\"'<>`()\[\]{},;|\\]*)", re.IGNORECASE)
RESERVED_HOSTS = ("example.com", "example.org", "example.net", ".example", ".test", ".invalid", "localhost")


def is_reserved(host: str) -> bool:
    return any(host == r.lstrip(".") or host.endswith("." + r.lstrip(".")) for r in RESERVED_HOSTS)


class Allow:
    def __init__(self, path: Path):
        self.hosts: set[str] = set()
        self.lines: list[tuple[str, re.Pattern]] = []
        if not path.is_file():
            return
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("host "):
                self.hosts.add(line.split(None, 1)[1].lower())
            else:
                glob, _, regex = line.partition(":")
                self.lines.append((glob, re.compile(regex)))

    def host(self, host: str) -> bool:
        return any(host == h or host.endswith("." + h) for h in self.hosts)

    def line(self, path: str, text: str) -> bool:
        return any(fnmatch.fnmatchcase(path, g) and r.search(text) for g, r in self.lines)


def ip_finding(text: str) -> tuple[str, str] | None:
    try:
        addr = ipaddress.IPv4Address(text)
    except ValueError:
        return None  # not an address (an octet over 255: a version string)
    if addr.is_loopback or addr.is_unspecified or text.startswith("255."):
        return None
    if any(addr in net for net in DOC_NETS):
        return None
    if addr in CGNAT or addr.is_link_local or addr.is_private:
        return ("private-ip", text)
    if addr.is_multicast or addr.is_reserved:
        return None
    return ("public-ip", text)


def findings_in_line(line: str, allow: Allow):
    for m in HOME_RE.finditer(line):
        if m.group(1) not in STOCK_USERS:
            yield "home-path", m.group(0)
    for m in IPV4_RE.finditer(line):
        hit = ip_finding(m.group(1))
        if hit:
            yield hit
    for m in IPV6_RE.finditer(line):
        try:
            ipaddress.IPv6Address(m.group(1).rstrip(":") + ("" if m.group(1).count("::") else "::"))
        except ValueError:
            continue
        yield "private-ip", m.group(1)
    for m in HOST_RE.finditer(line):
        yield "internal-host", m.group(1) or m.group(2)
    for m in EMAIL_RE.finditer(line):
        addr, domain = m.group(0).lower(), m.group(1).lower()
        if (
            addr in SSH_REMOTES
            or addr.endswith(SYSTEMD_SUFFIXES)
            or is_reserved(domain)
            or addr.startswith("noreply@")
            or domain.endswith("noreply.github.com")
        ):
            continue
        yield "email", m.group(0)
    for m in URL_RE.finditer(line):
        host = m.group(1).rsplit("@", 1)[-1].lower()
        host = re.sub(r":\d*$", "", host).rstrip(".")
        if "." not in host or not re.fullmatch(r"[a-z0-9.-]+", host):
            continue  # a variable, a regex, a placeholder: not a hostname
        if re.fullmatch(r"[\d.]+", host) or is_reserved(host) or allow.host(host):
            continue  # IP literals are judged by the address rules
        yield "server-url", m.group(0)


def tracked_files(root: Path) -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            capture_output=True,
            check=True,
        ).stdout
        names = [n for n in out.decode().split("\0") if n]
    except (subprocess.CalledProcessError, FileNotFoundError):
        names = [str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and ".git" not in p.parts]
    return sorted(n for n in names if (root / n).is_file())


def scan(root: Path) -> int:
    allow = Allow(root / ALLOW)
    count = 0
    files = [f for f in tracked_files(root) if f not in (SELF, ALLOW)]
    for rel in files:
        data = (root / rel).read_bytes()
        if b"\0" in data[:8192]:
            continue  # binary; public-hygiene.sh polices blobs
        for lineno, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
            for category, what in findings_in_line(line, allow):
                if allow.line(rel, line):
                    continue
                print(f"FAIL  [{category}] {rel}:{lineno}: {what}", file=sys.stderr)
                count += 1
    if count:
        print(f"Hard-coded configuration: {count} finding(s) in {len(files)} files.", file=sys.stderr)
        print(f"Fix them, or add a reviewed entry to {ALLOW}.", file=sys.stderr)
        return 1
    print(f"PASS  no hard-coded machine, network or personal configuration ({len(files)} files scanned)")
    return 0


# Fixture strings are assembled at run time so this file itself never holds a
# literal finding (public-hygiene.sh scans it too).
def _j(*parts: str) -> str:
    return "".join(parts)


BAD = {
    "home.sh": _j("cd /ho", "me/alice/src\n"),
    "mac.md": _j("see /Us", "ers/bob/notes\n"),
    "rfc1918.conf": _j("addr=10", ".1.2.3\n"),
    "rfc1918-172.conf": _j("peer 172", ".20.0.9\n"),
    "rfc1918-192.conf": _j("gw: 192", ".168.1.1/24\n"),
    "linklocal.conf": _j("169", ".254.10.20\n"),
    "cgnat.conf": _j("tailnet 100", ".100.1.2\n"),
    "public.conf": _j("server 8", ".8.8.8\n"),
    "ula.conf": _j("addr fd12:3456", "::1\n"),
    "ll6.conf": _j("fe80", "::1ff:fe23:4567:890a\n"),
    "host-local.sh": _j("ssh nas", ".local\n"),
    "host-lan.sh": _j("curl -s printer", ".lan/status\n"),
    "host-internal.yml": _j("url: db", ".internal\n"),
    "host-arpa.txt": _j("router", ".home", ".arpa\n"),
    "host-int.txt": _j("ci.int", ".acme.io\n"),
    "email.md": _j("ask alice", "@", "acme.io\n"),
    "url.sh": _j("curl https", "://ci.acme.io/api\n"),
    "url-port.sh": _j("http", "://grafana.acme.io:3000/d/x\n"),
}
GOOD = {
    "vars.sh": 'cd "$HOME/src"; ls /home/$USER ~/.local/share /home/alarm\n',
    "doc-ips.md": _j("192", ".0.2.10 198", ".51.100.7 203", ".0.113.5/24 127.0.0.1 0.0.0.0 255.255.255.0\n"),
    "versions.txt": _j("pkg|13.4.1.3-1|x 1.2.3.4-2 v10", ".0.0.1 linux=6.8.12.1021 0.17.2\n"),
    "hostname": "omarchy-jetson\n",
    "email.md": _j("noreply", "@", "github.com someone", "@", "example.com getty@tty1.service\n"),
    "remote.txt": _j("git", "@", "github.com:owner/repo.git\n"),
    "url.sh": _j(
        "https", "://github.com/x https", "://api.github.com/y http", "://localhost:8080/ https://example.com\n"
    ),
    "var-url.sh": _j("https", "://${host}/x file://${startdir}/f https", "://$server/a\n"),
    "allowed.md": _j("internal note for printer", ".lan\n"),
    "tests/no-hardcoded-config.allow": _j("host github.com\nallowed.md:printer\\", ".lan\n"),
}


def self_test() -> int:
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, body in BAD.items():
            case = Path(tmp) / ("bad-" + name)
            case.mkdir()
            (case / name).write_text(body)
            if scan_quiet(case) == 0:
                print(f"FAIL  self-test: {name} was not reported", file=sys.stderr)
                failures += 1
        good = Path(tmp) / "good"
        for name, body in GOOD.items():
            (good / name).parent.mkdir(parents=True, exist_ok=True)
            (good / name).write_text(body)
        if scan_quiet(good, show=True) != 0:
            print("FAIL  self-test: clean fixtures were reported", file=sys.stderr)
            failures += 1
    if failures:
        return 1
    print(f"PASS  hard-coded config scanner self-test ({len(BAD)} bad, {len(GOOD)} good fixtures)")
    return 0


def scan_quiet(root: Path, show: bool = False) -> int:
    import contextlib
    import io

    buf = io.StringIO()
    with contextlib.redirect_stderr(buf), contextlib.redirect_stdout(io.StringIO()):
        rc = scan(root)
    if show and rc:
        sys.stderr.write(buf.getvalue())
    return rc


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "--scan":
        return scan(Path(argv[1]).resolve())
    if argv:
        print(__doc__, file=sys.stderr)
        return 2
    rc = self_test()
    return scan(REPO) or rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
