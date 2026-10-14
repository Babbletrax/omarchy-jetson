#!/usr/bin/env bash
set -Eeuo pipefail

readonly KERNEL_RELEASE='6.8.12-1021-tegra'
readonly MODULE_ROOT="usr/lib/modules/$KERNEL_RELEASE"
readonly SOURCE_DATE_EPOCH='1786117320'
readonly REQUIRED_MODULES=(
  'kernel/drivers/phy/tegra/phy-tegra194-p2u.ko'
  'kernel/drivers/pci/controller/dwc/pcie-tegra194.ko'
  'kernel/drivers/nvme/host/nvme-core.ko'
  'kernel/drivers/nvme/host/nvme.ko'
)

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base_initrd="$repo_root/build/nvidia-bsp/Linux_for_Tegra/bootloader/l4t_initrd.img"
lock_file="$repo_root/config/inputs.lock.json"

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

if (($# != 2)); then
  printf 'Usage: %s ROOTFS OUTPUT_INITRD\n' "$0" >&2
  exit 2
fi

rootfs=$1
output=$2
[[ "$rootfs" == /* ]] || rootfs="$PWD/$rootfs"
[[ "$output" == /* ]] || output="$PWD/$output"

[[ -d "$rootfs/$MODULE_ROOT" ]] || fail "missing module tree: $rootfs/$MODULE_ROOT"
[[ -f "$base_initrd" ]] || fail "missing base initrd: $base_initrd"
[[ ! -e "$output" ]] || fail "output path already exists: $output"
[[ -d "$(dirname "$output")" ]] || fail "output parent does not exist: $(dirname "$output")"

for command_name in awk chmod cp cpio dirname find gzip install jq mkdir mktemp rm sha256sum sort touch; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing host command: $command_name"
done

expected_sha256=$(jq -er '.artifacts.nvidia_jetson_linux_bsp.l4t_initrd_sha256' "$lock_file")
actual_sha256=$(sha256sum "$base_initrd" | awk '{print $1}')
[[ "$actual_sha256" == "$expected_sha256" ]] || fail 'base initrd SHA-256 does not match input lock'
pass 'base initrd SHA-256 matches input lock'

workdir=$(mktemp -d /tmp/omarchy-initrd.XXXXXX)
cleanup() {
  chmod -R u+w "$workdir"
  rm -r "$workdir"
}
trap cleanup EXIT

(
  cd "$workdir"
  gzip -dc "$base_initrd" | cpio -idmu --quiet --no-absolute-filenames
)

mkdir -p "$workdir/$MODULE_ROOT"
for index in "$rootfs/$MODULE_ROOT"/modules*; do
  [[ -f "$index" ]] || continue
  cp -a "$index" "$workdir/$MODULE_ROOT/"
done

for relative_module in "${REQUIRED_MODULES[@]}"; do
  source_module="$rootfs/$MODULE_ROOT/$relative_module"
  [[ -f "$source_module" ]] || fail "missing required module: $source_module"
  install -Dm644 "$source_module" "$workdir/$MODULE_ROOT/$relative_module"
done

if [[ -d "$rootfs/etc/modprobe.d" ]]; then
  mkdir -p "$workdir/etc/modprobe.d"
  for config_file in "$rootfs/etc/modprobe.d"/*.conf; do
    [[ -f "$config_file" ]] || continue
    cp -a "$config_file" "$workdir/etc/modprobe.d/"
  done
fi

find "$workdir" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

(
  cd "$workdir"
  find . -print0 | LC_ALL=C sort -z |
    cpio --null --format=newc --owner=0:0 --reproducible --quiet -o |
    gzip -9 -n > "$output"
)

[[ -s "$output" ]] || fail 'generated initrd is empty'
for relative_module in "${REQUIRED_MODULES[@]}"; do
  gzip -dc "$output" | cpio -t --quiet 2>/dev/null |
    awk -v wanted="$MODULE_ROOT/$relative_module" '$0 == wanted {found=1} END {exit !found}' ||
    fail "generated initrd lacks $relative_module"
done
gzip -dc "$output" | cpio -t --quiet 2>/dev/null |
  awk '$0 == "init" {found=1} END {exit !found}' || fail 'generated initrd lacks init'

pass "generated initrd contains ${#REQUIRED_MODULES[@]} required Orin NVMe modules"
sha256sum "$output"
