#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
checker="$repo_root/scripts/check-upstreams.py"

# Offline: this asserts the pins are coherent, not that they are current.
# Reaching GitHub belongs in a scheduled job, not a test run on every commit.
[[ -x $checker ]]
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$checker"

# Every vendored upstream must be pinned to an exact tag or commit. A floating
# ref would make a build unreproducible and silently pull unreviewed code into
# a package that patches it.
while IFS= read -r pkgbuild; do
  grep -q 'github.com' "$pkgbuild" || continue
  name=$(basename "$(dirname "$pkgbuild")")
  if grep -qE "^_commit=['\"]?[0-9a-f]{40}" "$pkgbuild"; then
    continue
  fi
  if grep -qE '^pkgver=[0-9]' "$pkgbuild"; then
    continue
  fi
  printf 'FAIL  %s pins no exact tag or commit\n' "$name" >&2
  exit 1
done < <(find "$repo_root/packages" -name PKGBUILD)

# A package that patches its upstream must guard the patch, so a moved line
# fails the build instead of silently shipping unpatched.
while IFS= read -r pkgbuild; do
  grep -q 'sed -i' "$pkgbuild" || continue
  name=$(basename "$(dirname "$pkgbuild")")
  if ! grep -q 'no longer matches' "$pkgbuild"; then
    printf 'FAIL  %s patches upstream without a guard\n' "$name" >&2
    exit 1
  fi
done < <(find "$repo_root/packages" -name PKGBUILD)

# Nothing may ship with SKIP for the upstream archive: the checksum is the only
# thing tying a pinned ref to the bytes that were reviewed.
while IFS= read -r pkgbuild; do
  grep -q 'github.com' "$pkgbuild" || continue
  name=$(basename "$(dirname "$pkgbuild")")
  if grep -qE "^\s*'?SKIP'?\s*$" "$pkgbuild"; then
    printf 'FAIL  %s ships a SKIP checksum for a vendored upstream\n' "$name" >&2
    exit 1
  fi
done < <(find "$repo_root/packages" -name PKGBUILD)

printf 'PASS  vendored upstreams pinned exactly, patches guarded, checksums present\n'
