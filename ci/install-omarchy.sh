#!/usr/bin/env bash
# Unpack upstream Omarchy's files (/usr/share/omarchy and its /usr/bin commands,
# which the share/bin entries link to) for the regression suites, without its
# dependencies. Works with or without pacman (Arch Linux ARM or an Ubuntu CI
# runner): the package is fetched from the Omarchy repository and its detached
# signature checked with gpgv against the signing key committed in ci/keys/ and
# pinned by fingerprint in config/versions.env. No key is fetched at run time.
#
#   ci/install-omarchy.sh pinned   the version packages/omarchy-jetson-upstream builds against
#   ci/install-omarchy.sh latest   whatever the Omarchy repository serves now (early warning)
#
# Environment: OMARCHY_ROOT (default /) is where the files are unpacked;
# OMARCHY_REPO_URL overrides the repository (default from config/versions.env).
# Needs curl, gpg/gpgv, bsdtar (libarchive-tools) and zstd; run as root for /.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-pinned}
# shellcheck disable=SC1091
source "$repo_root/config/versions.env"
arch=aarch64
repo_url=${OMARCHY_REPO_URL:-$OMARCHY_PACKAGE_REPOSITORY/$arch}
dest=${OMARCHY_ROOT:-/}

cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT

fetch() { curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$1" "$2"; }

case $mode in
  latest)
    # The repository database is unsigned; the package it names is verified
    # below, so a tampered database can at worst pick a different signed build.
    fetch "$cache/omarchy.db" "$repo_url/omarchy.db"
    file=$(bsdtar -xOf "$cache/omarchy.db" 'omarchy-[0-9]*/desc' |
      awk '/^%FILENAME%$/ {getline; print; exit}')
    [[ $file =~ ^omarchy-[0-9][^/]*-$arch\.pkg\.tar\.zst$ ]] || {
      echo "no omarchy package in $repo_url/omarchy.db" >&2
      exit 1
    }
    fetch "$cache/$file" "$repo_url/$file"
    fetch "$cache/$file.sig" "$repo_url/$file.sig"
    pkg=$cache/$file
    ;;
  pinned)
    ver=$(sed -n 's/^pkgver=//p' "$repo_root/packages/omarchy-jetson-upstream/PKGBUILD")
    [[ -n $ver ]] || {
      echo "no pkgver in omarchy-jetson-upstream" >&2
      exit 1
    }
    # The newest pkgrel of the pinned version that the repository still has.
    pkg=
    for rel in 1 2 3 4 5 6 7 8 9; do
      f=omarchy-$ver-$rel-$arch.pkg.tar.zst
      if curl -fsSL --proto '=https' --tlsv1.2 -o "$cache/$f" "$repo_url/$f" 2>/dev/null; then
        fetch "$cache/$f.sig" "$repo_url/$f.sig"
        pkg=$cache/$f
      elif [[ -n $pkg ]]; then
        break
      fi
    done
    [[ -n $pkg ]] || {
      echo "omarchy $ver not found at $repo_url" >&2
      exit 1
    }
    ;;
  *)
    echo "usage: $0 pinned|latest" >&2
    exit 2
    ;;
esac

"$repo_root/ci/verify-signature.sh" "$repo_root/ci/keys/omarchy.asc" "$OMARCHY_SIGNING_KEY" "$pkg.sig" "$pkg"
mkdir -p "$dest"
bsdtar -xf "$pkg" -C "$dest" usr/share/omarchy 'usr/bin/omarchy*'
echo "Omarchy files from $(basename "$pkg") unpacked into $dest"
