#!/usr/bin/env bash
set -Eeuo pipefail

readonly MIN_FREE_GIB=150
failures=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; failures=$((failures + 1)); }

if [[ "$(uname -s)" == 'Linux' ]]; then
  pass 'host operating system is Linux'
else
  fail 'host operating system must be Linux'
fi

case "$(uname -m)" in
  x86_64|aarch64) pass "host architecture is $(uname -m)" ;;
  *) fail "unsupported host architecture: $(uname -m)" ;;
esac

for command_name in bash bsdtar curl findmnt git gpg jq lsblk openssl sha256sum tar unshare usermod; do
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "found $command_name"
  else
    fail "missing $command_name"
  fi
done

available_kib=$(df -Pk . | awk 'NR == 2 {print $4}')
if [[ "$available_kib" =~ ^[0-9]+$ ]]; then
  available_gib=$((available_kib / 1024 / 1024))
  if ((available_gib >= MIN_FREE_GIB)); then
    pass "workspace has ${available_gib} GiB free"
  else
    warn "workspace has ${available_gib} GiB free; ${MIN_FREE_GIB} GiB recommended"
  fi
else
  fail 'could not determine workspace free space'
fi

if [[ -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
  pass 'AArch64 binfmt handler is registered'
elif command -v qemu-aarch64-static >/dev/null 2>&1; then
  warn 'qemu-aarch64-static exists but binfmt handler is not registered'
else
  warn 'no AArch64 execution helper detected; offline assembly remains possible'
fi

if ((failures > 0)); then
  printf '\nHost preflight failed with %d blocking issue(s).\n' "$failures" >&2
  exit 1
fi

printf '\nHost preflight passed. Warnings require review before image construction.\n'
