#!/usr/bin/env bash
# Offline fixture tests for the CI helpers in ci/: pinned-key signature
# verification, the committed signing keys, and the Markdown link checker.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  failures=$((failures + 1))
}
expect() { # name want-exit command...
  local name=$1 want=$2 got=0
  shift 2
  "$@" >"$work/out" 2>&1 || got=$?
  if [[ $got == "$want" ]]; then pass "$name"; else
    fail "$name (exit $got, want $want)"
    cat "$work/out" >&2
  fi
}

# shellcheck disable=SC1091
source "$repo_root/config/versions.env"

# --- the helpers parse and pass ShellCheck (tests/static.sh covers scripts/
# and tests/) ------------------------------------------------------------------
for script in "$repo_root"/ci/*.sh; do
  if bash -n "$script"; then pass "bash -n ci/${script##*/}"; else fail "bash -n ci/${script##*/}"; fi
done
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$repo_root"/ci/*.sh; then pass 'shellcheck ci/*.sh'; else fail 'shellcheck ci/*.sh'; fi
else
  printf 'WARN  shellcheck unavailable; CI will enforce it\n'
fi
if python3 -I -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' "$repo_root"/ci/*.py; then pass 'ci/*.py compile'; else fail 'ci/*.py compile'; fi

# --- committed keys are the pinned ones ---------------------------------------
key_fpr() {
  GNUPGHOME=$work/show gpg --batch --with-colons --show-keys "$1" 2>/dev/null |
    awk -F: '$1 == "pub" {w = 1; next} w && $1 == "fpr" {print $10; w = 0}'
}
mkdir -m 0700 "$work/show"
same() { # name actual expected
  if [[ $2 == "$3" ]]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}
same 'ci/keys/omarchy.asc is exactly the pinned Omarchy key' \
  "$(key_fpr "$repo_root/ci/keys/omarchy.asc")" "$OMARCHY_SIGNING_KEY"
same 'ci/keys/archlinuxarm-build.asc is exactly the pinned Arch Linux ARM key' \
  "$(key_fpr "$repo_root/ci/keys/archlinuxarm-build.asc")" "$ARCH_ROOTFS_SIGNING_KEY"
same 'rootfs signing key agrees with the input lock' \
  "$(jq -r .artifacts.archlinuxarm_rootfs.signing_key_fingerprint "$repo_root/config/inputs.lock.json")" "$ARCH_ROOTFS_SIGNING_KEY"

# --- ci/verify-signature.sh ---------------------------------------------------
verify=$repo_root/ci/verify-signature.sh
gen_key() { # home name
  mkdir -m 0700 "$1"
  GNUPGHOME=$1 gpg --batch --quiet --passphrase '' --quick-gen-key "$2 <$2@example.com>" ed25519 sign never 2>/dev/null
  GNUPGHOME=$1 gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}'
}
fpr_a=$(gen_key "$work/a" signer-a)
fpr_b=$(gen_key "$work/b" signer-b)
GNUPGHOME=$work/a gpg --batch --armor --export >"$work/a.asc" 2>/dev/null
GNUPGHOME=$work/b gpg --batch --armor --export >"$work/b.asc" 2>/dev/null
cat "$work/a.asc" "$work/b.asc" >"$work/both.asc"
printf 'payload\n' >"$work/file"
GNUPGHOME=$work/a gpg --batch --quiet --detach-sign -o "$work/file.sig" "$work/file" 2>/dev/null
cp "$work/file" "$work/tampered" && printf 'x' >>"$work/tampered"

expect 'verify: good signature, pinned key' 0 "$verify" "$work/a.asc" "$fpr_a" "$work/file.sig" "$work/file"
expect 'verify: lower-case fingerprint accepted' 0 "$verify" "$work/a.asc" "${fpr_a,,}" "$work/file.sig" "$work/file"
expect 'verify: tampered file rejected' 1 "$verify" "$work/a.asc" "$fpr_a" "$work/file.sig" "$work/tampered"
expect 'verify: signature by another key rejected' 1 "$verify" "$work/b.asc" "$fpr_b" "$work/file.sig" "$work/file"
expect 'verify: key file not matching the pin rejected' 1 "$verify" "$work/b.asc" "$fpr_a" "$work/file.sig" "$work/file"
expect 'verify: key file with an extra key rejected' 1 "$verify" "$work/both.asc" "$fpr_a" "$work/file.sig" "$work/file"
expect 'verify: short key id rejected' 2 "$verify" "$work/a.asc" "${fpr_a: -16}" "$work/file.sig" "$work/file"

# --- ci/check-doc-links.py ------------------------------------------------------
links=$repo_root/ci/check-doc-links.py
mkdir -p "$work/docs/good/sub" "$work/docs/bad"
cat >"$work/docs/good/README.md" <<'EOF'
# Top

See [the guide](sub/guide.md#set-up-the-board), [here](#top), [a dir](sub/),
[external](https://example.com/missing) and ![img](sub/pic.png).

[ref]: sub/guide.md
<a href="sub/guide.md#second-step-2">html</a>

```sh
[not a link](missing.md)
```
EOF
cat >"$work/docs/good/sub/guide.md" <<'EOF'
# Set up the board
## Second `step` (2)
EOF
: >"$work/docs/good/sub/pic.png"
printf '# Doc\n\n[gone](missing.md)\n' >"$work/docs/bad/a.md"
printf '# Doc\n\n[bad anchor](a.md#nope)\n' >"$work/docs/bad/b.md"
expect 'doc links: valid relative links and anchors pass' 0 python3 -I "$links" "$work/docs/good"
expect 'doc links: missing file and anchor fail' 1 python3 -I "$links" "$work/docs/bad"
if grep -q 'missing.md: no such file' "$work/out" && grep -q 'a.md#nope: no heading' "$work/out"; then
  pass 'doc links: both broken links reported'
else
  fail 'doc links: broken links not reported'
  cat "$work/out" >&2
fi

((failures == 0)) || exit 1
