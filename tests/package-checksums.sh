#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Every source a PKGBUILD takes from this repository (a plain file beside it, or
# file://${startdir}/...) must match its recorded sha256sum. Otherwise an edit
# that forgot updpkgsums only fails later, at makepkg time.
fail=0
checked=0
while IFS= read -r pkgbuild; do
  dir=$(dirname "$pkgbuild")
  while IFS=$'\t' read -r src sum; do
    [[ $sum == SKIP ]] && continue
    entry=${src#*::}
    case $entry in
      file://*) path=${entry#file://} ;;
      *://*) continue ;;
      *) path=$dir/$entry ;;
    esac
    # Build inputs from outside the repository (the NVIDIA BSP tree) are
    # checked by makepkg against the real files.
    path=$(realpath -m "$path")
    [[ $path == "$repo_root"/* ]] || continue
    [[ -f $path ]] || { printf 'FAIL  %s: source %s not found\n' "${dir##*/}" "$entry" >&2; fail=1; continue; }
    actual=$(sha256sum "$path" | cut -d' ' -f1)
    checked=$((checked + 1))
    if [[ $actual != "$sum" ]]; then
      printf 'FAIL  %s: %s sha256sum is stale (run updpkgsums)\n' "${dir##*/}" "${path#"$repo_root"/}" >&2
      fail=1
    fi
  done < <(
    cd "$dir" && JETSON_BSP_DIR=/nonexistent JETSON_INITRD=/nonexistent startdir=$dir bash -c '
      source ./PKGBUILD >/dev/null 2>&1
      for i in "${!source[@]}"; do printf "%s\t%s\n" "${source[$i]}" "${sha256sums[$i]:-}"; done'
  )
done < <(find "$repo_root/packages" -name PKGBUILD | sort)

((fail == 0)) || exit 1
printf 'PASS  local package sources match their sha256sums (%d checked)\n' "$checked"
