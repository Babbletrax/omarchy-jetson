#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
cleanup() { find "$fixture" -depth -delete; }
trap cleanup EXIT
mkdir -p "$fixture/input"
printf '%s\n' package >"$fixture/input/example-1-aarch64.pkg.tar.xz"
printf '%s\n' rootfs >"$fixture/input/omarchy-rootfs.tar"
openssl genpkey -algorithm ED25519 -out "$fixture/release.key" >/dev/null 2>&1
builder=$repo_root/scripts/build-release-channel.sh

"$builder" --input "$fixture/input" --output "$fixture/out-a" --private-key "$fixture/release.key" --source-date-epoch 1788422400 >/dev/null
"$builder" --input "$fixture/input" --output "$fixture/out-b" --private-key "$fixture/release.key" --source-date-epoch 1788422400 >/dev/null
diff -r "$fixture/out-a" "$fixture/out-b" >/dev/null
(
  cd "$fixture/out-a"
  sha256sum --check SHA256SUMS >/dev/null
  openssl pkeyutl -verify -rawin -pubin -inkey release-signing-public.pem -in SHA256SUMS -sigfile SHA256SUMS.sig >/dev/null
)
printf '%s\n' tampered >>"$fixture/out-a/artifacts/omarchy-rootfs.tar"
if (cd "$fixture/out-a" && sha256sum --check SHA256SUMS >/dev/null 2>&1); then exit 1; fi
printf '%s\n' 'PASS  reproducible signed release channel and tamper rejection fixture'
