#!/usr/bin/env python3
"""Check relative links in the repository's Markdown files, offline.

Every [text](target), [label]: target and <a href|img src="target"> that is
not an external URL must name a file or directory that exists, and a
#fragment must match a heading in the target Markdown file (GitHub's anchor
rules). External links are not fetched: that would make CI depend on other
people's servers.

  ci/check-doc-links.py [ROOT]
"""

from __future__ import annotations

import re
import subprocess
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote

INLINE = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REFDEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+.*)?$")
HTML = re.compile(r"<(?:a|img)\b[^>]*?\b(?:href|src)=\"([^\"]+)\"", re.IGNORECASE)
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$")
EXTERNAL = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|//)", re.IGNORECASE)


def slug(text: str) -> str:
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text).strip().lower()
    out = []
    for ch in text:
        cat = unicodedata.category(ch)
        if ch in "-_" or cat[0] in "LN" or cat == "Mn":
            out.append(ch)
        elif ch == " ":
            out.append("-")
    return "".join(out)


def strip_code(lines: list[str], inline: bool = True) -> list[tuple[int, str]]:
    kept, fence = [], None
    for n, line in enumerate(lines, 1):
        m = FENCE.match(line)
        if m:
            if fence is None:
                fence = m.group(1)[0]
            elif m.group(1)[0] == fence:
                fence = None
            continue
        if fence is None:
            kept.append((n, re.sub(r"`[^`]*`", "", line) if inline else line))
    return kept


_anchors: dict[Path, set[str]] = {}


def anchors(path: Path) -> set[str]:
    if path not in _anchors:
        seen: dict[str, int] = {}
        found = set()
        for _, line in strip_code(path.read_text(encoding="utf-8").splitlines(), inline=False):
            m = HEADING.match(line)
            if not m:
                continue
            base = slug(m.group(1))
            n = seen.get(base, 0)
            seen[base] = n + 1
            found.add(base if n == 0 else f"{base}-{n}")
        found.update(re.findall(r"<a\s+(?:name|id)=\"([^\"]+)\"", path.read_text(encoding="utf-8")))
        _anchors[path] = found
    return _anchors[path]


def markdown_files(root: Path) -> list[Path]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard", "*.md"],
            capture_output=True,
            check=True,
        ).stdout.decode()
        return sorted(root / n for n in out.split("\0") if n and (root / n).is_file())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return sorted(p for p in root.rglob("*.md") if ".git" not in p.parts)


def check(root: Path) -> int:
    failures = 0
    files = markdown_files(root)
    for md in files:
        rel = md.relative_to(root)
        for lineno, line in strip_code(md.read_text(encoding="utf-8").splitlines()):
            targets = [m.group(1) for m in INLINE.finditer(line)]
            targets += [m.group(1) for m in HTML.finditer(line)]
            m = REFDEF.match(line)
            if m:
                targets.append(m.group(1))
            for target in targets:
                if EXTERNAL.match(target):
                    continue
                path_part, _, fragment = target.partition("#")
                path_part = unquote(path_part.split("?", 1)[0])
                if path_part.startswith("/"):
                    dest = root / path_part.lstrip("/")
                elif path_part:
                    dest = md.parent / path_part
                else:
                    dest = md
                problem = None
                if not dest.exists():
                    problem = "no such file"
                elif fragment and dest.suffix == ".md" and dest.is_file():
                    if unquote(fragment).lower() not in anchors(dest):
                        problem = f"no heading #{fragment}"
                elif dest.resolve() != root.resolve() and root.resolve() not in dest.resolve().parents:
                    problem = "points outside the repository"
                if problem:
                    print(f"FAIL  {rel}:{lineno}: {target}: {problem}", file=sys.stderr)
                    failures += 1
    if failures:
        print(f"{failures} broken relative link(s) in {len(files)} Markdown files.", file=sys.stderr)
        return 1
    print(f"PASS  relative links in {len(files)} Markdown files")
    return 0


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()))
