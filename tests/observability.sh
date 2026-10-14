#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/sys/class/thermal/thermal_zone0" "$fixture/sys/class/thermal/thermal_zone1" \
  "$fixture/sys/class/hwmon/hwmon0" "$fixture/sys/devices/nvme/nvme0" \
  "$fixture/sys/class/devfreq/17000000.gpu" "$fixture/sys/class/devfreq/bwmgr" \
  "$fixture/sys/devices/platform/bus@0/17000000.gpu" "$fixture/proc"
printf 'cpu-thermal\n' >"$fixture/sys/class/thermal/thermal_zone0/type"
printf '51000\n' >"$fixture/sys/class/thermal/thermal_zone0/temp"
printf 'gpu-thermal\n' >"$fixture/sys/class/thermal/thermal_zone1/type"
printf '47000\n' >"$fixture/sys/class/thermal/thermal_zone1/temp"
printf 'nvme\n' >"$fixture/sys/class/hwmon/hwmon0/name"
ln -s "$fixture/sys/devices/nvme/nvme0" "$fixture/sys/class/hwmon/hwmon0/device"
printf 'Composite\n' >"$fixture/sys/class/hwmon/hwmon0/temp1_label"
printf '42000\n' >"$fixture/sys/class/hwmon/hwmon0/temp1_input"
printf '300\n' >"$fixture/sys/devices/platform/bus@0/17000000.gpu/load"
printf '612000000\n' >"$fixture/sys/class/devfreq/17000000.gpu/cur_freq"
printf '1300500000\n' >"$fixture/sys/class/devfreq/17000000.gpu/max_freq"
printf '2133000000\n' >"$fixture/sys/class/devfreq/bwmgr/cur_freq"
printf '3199000000\n' >"$fixture/sys/class/devfreq/bwmgr/max_freq"
printf 'MemTotal: 64000000 kB\nMemAvailable: 32000000 kB\nSwapTotal: 16000000 kB\nSwapFree: 15000000 kB\n' >"$fixture/proc/meminfo"

status="$repo_root/packages/omarchy-jetson-observability/omarchy-jetson-status"
json=$(OMARCHY_SYS_ROOT="$fixture/sys" OMARCHY_PROC_ROOT="$fixture/proc" "$status" --json)
jq -e '.cpu_temp_millic == "51000" and .gpu_temp_millic == "47000" and
  .nvme_temp_millic == "42000" and .gpu_load_permille == "300" and
  .unified_memory_kib.available == "32000000"' <<<"$json" >/dev/null
if rg -q 'mmc' <<<"$json"; then
  printf 'FAIL observability output referenced eMMC\n' >&2
  exit 1
fi
support="$repo_root/packages/omarchy-jetson-observability/omarchy-jetson-support"
redacted=$(printf '%s\n' 'token=abc password: xyz Authorization=Bearer123 op://vault/item/field 192.0.2.10' |
  "$support" --redact)
rg -q '\[REDACTED\]' <<<"$redacted"
if rg -q 'abc|xyz|Bearer123|vault/item|192\.0\.2\.10' <<<"$redacted"; then
  printf 'FAIL support redaction retained a synthetic secret\n' >&2
  exit 1
fi
rg -Fq -- '--since=-2h -n 500' "$support"
printf 'PASS  named Jetson/NVMe sensors and unified-memory fixture\n'
