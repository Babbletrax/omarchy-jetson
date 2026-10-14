#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
archive="$repo_root/artifacts/archlinuxarm/ArchLinuxARM-aarch64-latest.tar.gz"
lock_file="$repo_root/config/inputs.lock.json"

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

if [[ "${OMARCHY_ASSEMBLY_NAMESPACE:-0}" != 1 ]]; then
  if (($# != 1)); then
    printf 'Usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
    exit 2
  fi

  output=$1
  [[ "$output" == /* ]] || output="$PWD/$output"
  [[ -f "$archive" ]] || fail "missing pinned rootfs archive: $archive"
  [[ -f "$lock_file" ]] || fail "missing input lock: $lock_file"
  [[ ! -e "$output" ]] || fail "output path already exists: $output"
  [[ -d "$(dirname "$output")" ]] || fail "output parent does not exist: $(dirname "$output")"

  for command_name in awk bsdtar find jq sha256sum unshare usermod wc; do
    command -v "$command_name" >/dev/null 2>&1 || fail "missing host command: $command_name"
  done

  expected_sha256=$(jq -er '.artifacts.archlinuxarm_rootfs.sha256' "$lock_file")
  actual_sha256=$(sha256sum "$archive" | awk '{print $1}')
  [[ "$actual_sha256" == "$expected_sha256" ]] || fail 'rootfs SHA-256 does not match input lock'
  pass 'rootfs SHA-256 matches input lock'

  expected_entries=$(bsdtar -tf "$archive" | wc -l)
  export OMARCHY_ASSEMBLY_NAMESPACE=1
  export OMARCHY_ASSEMBLY_ARCHIVE="$archive"
  export OMARCHY_ASSEMBLY_OUTPUT="$output"
  export OMARCHY_ASSEMBLY_EXPECTED_ENTRIES="$expected_entries"

  exec unshare --user --map-auto --map-root-user "$BASH" "$0" --inside-namespace
fi

[[ "${1:-}" == '--inside-namespace' ]] || fail 'invalid namespace invocation'
[[ $(id -u) == 0 && $(id -g) == 0 ]] || fail 'assembly namespace is not root-mapped'

archive=${OMARCHY_ASSEMBLY_ARCHIVE:?}
output=${OMARCHY_ASSEMBLY_OUTPUT:?}
expected_entries=${OMARCHY_ASSEMBLY_EXPECTED_ENTRIES:?}

mkdir "$output"
bsdtar --numeric-owner -xpf "$archive" -C "$output"

for account in root alarm; do
  usermod --prefix "$output" --lock "$account"
done

if awk -F: '$2 !~ /^(!|\*|$)/ {print $1; found=1} END {exit found}' "$output/etc/shadow"; then
  pass 'no password-enabled accounts remain'
else
  fail 'one or more password-enabled accounts remain'
fi

[[ ! -s "$output/etc/machine-id" ]] || fail 'machine-id is populated'
pass 'machine-id will be generated on first boot'

ssh_key_count=$(find "$output/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -print 2>/dev/null | wc -l)
[[ "$ssh_key_count" == 0 ]] || fail "rootfs contains $ssh_key_count SSH host key files"
pass 'SSH host keys will be generated on first boot'

actual_nodes=$(find "$output" -mindepth 1 -printf . | wc -c)
[[ "$actual_nodes" == "$expected_entries" ]] || fail "node count $actual_nodes does not match archive entry count $expected_entries"
pass "extracted $actual_nodes filesystem nodes"

[[ $(stat -c '%u:%g:%a' "$output/etc/shadow") == '0:0:600' ]] || fail 'shadow ownership or mode mismatch'
[[ $(stat -c '%u:%g:%a' "$output/home/alarm") == '1000:1000:700' ]] || fail 'alarm home ownership or mode mismatch'
pass 'sampled numeric ownership and modes match the source archive'

printf 'Base rootfs assembly passed: %s\n' "$output"
