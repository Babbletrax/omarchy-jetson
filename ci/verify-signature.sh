#!/usr/bin/env bash
# Verify a detached OpenPGP signature against one public key that is committed
# to this repository and pinned by its full fingerprint. Never fetches a key:
# the key file must contain exactly the expected primary key.
#   ci/verify-signature.sh KEY.asc FINGERPRINT FILE.sig FILE
set -Eeuo pipefail

key=$1 fingerprint=${2^^} sig=$3 file=$4
[[ $fingerprint =~ ^[0-9A-F]{40}$ ]] || {
  echo "not a full fingerprint: $2" >&2
  exit 2
}

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
chmod 0700 "$home"

primaries=$(gpg --homedir "$home" --batch --with-colons --show-keys "$key" 2>/dev/null |
  awk -F: '$1 == "pub" {want = 1; next} want && $1 == "fpr" {print $10; want = 0}')
if [[ $primaries != "$fingerprint" ]]; then
  printf '%s does not hold exactly key %s (found: %s)\n' "$key" "$fingerprint" "${primaries:-none}" >&2
  exit 1
fi

gpg --homedir "$home" --batch --quiet --dearmor --output "$home/keyring.gpg" "$key"
if gpgv --keyring "$home/keyring.gpg" "$sig" "$file" 2>"$home/gpgv.log"; then
  printf 'signature OK: %s (key %s)\n' "${file##*/}" "$fingerprint"
else
  cat "$home/gpgv.log" >&2
  printf 'BAD signature on %s\n' "$file" >&2
  exit 1
fi
