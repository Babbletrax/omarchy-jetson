#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
compatibility=$repo_root/config/release-compatibility.json
input=
output=
private_key=
epoch=${SOURCE_DATE_EPOCH:-}

die() { printf 'ERROR %s\n' "$*" >&2; exit 2; }
while (($#)); do
  case $1 in
    --input) input=${2:-}; shift 2 ;;
    --output) output=${2:-}; shift 2 ;;
    --private-key) private_key=${2:-}; shift 2 ;;
    --source-date-epoch) epoch=${2:-}; shift 2 ;;
    *) die 'usage: build-release-channel.sh --input DIR --output NEW_DIR --private-key FILE --source-date-epoch UNIX_TIME' ;;
  esac
done

[[ $input == /* && -d $input ]] || die 'input must be an absolute directory'
[[ $output == /* && ! -e $output ]] || die 'output must be a new absolute path'
[[ $private_key == /* && -f $private_key && ! -L $private_key ]] || die 'private key must be an absolute regular file, not a symlink'
[[ $epoch =~ ^[0-9]+$ ]] || die 'SOURCE_DATE_EPOCH must be an unsigned integer'
((epoch > 0)) || die 'SOURCE_DATE_EPOCH must be positive'
jq -e '.schema == 1 and .architecture == "aarch64" and .board_config == "jetson-agx-orin-devkit" and .modules == ["P3701-0005"] and .jetson_linux == "39.2.1" and .kernel == "6.8.12-1021-tegra" and .root_device == "nvme0n1p1"' "$compatibility" >/dev/null || die 'compatibility matrix is invalid'
openssl pkey -in "$private_key" -noout >/dev/null || die 'private key is invalid'

mapfile -d '' artifacts < <(find "$input" -maxdepth 1 -type f \
  \( -name '*.pkg.tar.xz' -o -name '*.pkg.tar.zst' -o -name '*.img' -o -name '*rootfs*.tar' \) -print0 | sort -z)
((${#artifacts[@]} > 0)) || die 'no release artifacts found'
printf '%s\0' "${artifacts[@]}" | grep -zqE '\.pkg\.tar\.(xz|zst)$' || die 'release requires at least one package'
printf '%s\0' "${artifacts[@]}" | grep -zqE '(\.img|rootfs.*\.tar)$' || die 'release requires an image or rootfs archive'

install -d -m 700 "$output/artifacts"
declare -A names=()
for artifact in "${artifacts[@]}"; do
  name=${artifact##*/}
  [[ $name != *$'\n'* && $name != *$'\r'* ]] || die 'artifact names may not contain line breaks'
  [[ -z ${names[$name]:-} ]] || die "duplicate artifact basename: $name"
  names[$name]=1
  cp --reflink=auto --preserve=mode "$artifact" "$output/artifacts/$name"
  touch --date="@$epoch" "$output/artifacts/$name"
done

cp "$compatibility" "$output/compatibility.json"
created=$(date -u --date="@$epoch" +%Y-%m-%dT%H:%M:%SZ)
(
  cd "$output"
  find artifacts -maxdepth 1 -type f -print0 | sort -z | xargs -0 sha256sum |
    jq -Rsc --arg created "$created" '
      split("\n") | map(select(length > 0) | capture("^(?<sha256>[0-9a-f]{64})  (?<name>.+)$")) |
      {schema:1,created_at:$created,artifacts:.}' >release.json
  sha256sum compatibility.json release.json artifacts/* >SHA256SUMS
)
openssl pkey -in "$private_key" -pubout -out "$output/release-signing-public.pem"
openssl pkeyutl -sign -rawin -inkey "$private_key" -in "$output/SHA256SUMS" -out "$output/SHA256SUMS.sig"
touch --date="@$epoch" "$output/compatibility.json" "$output/release.json" "$output/SHA256SUMS" "$output/SHA256SUMS.sig" "$output/release-signing-public.pem"
(
  cd "$output"
  sha256sum --check SHA256SUMS >/dev/null
  openssl pkeyutl -verify -rawin -pubin -inkey release-signing-public.pem -in SHA256SUMS -sigfile SHA256SUMS.sig >/dev/null
)
printf 'Built signed release channel %s\n' "$output"
