#!/usr/bin/env bash
set -Eeuo pipefail

read_text_file() {
  local path=$1
  if [[ -r "$path" ]]; then
    tr -d '\000' <"$path"
  else
    printf 'unavailable'
  fi
}

printf 'report_version=1\n'
printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'model=%s\n' "$(read_text_file /proc/device-tree/model)"
printf 'compatible='
if [[ -r /proc/device-tree/compatible ]]; then
  tr '\000' ',' </proc/device-tree/compatible
else
  printf 'unavailable'
fi
printf '\n'
printf 'kernel=%s\n' "$(uname -srvm)"
printf 'machine=%s\n' "$(uname -m)"
printf 'os_release_begin\n'
if [[ -r /etc/os-release ]]; then sed -n '1,40p' /etc/os-release; else printf 'unavailable\n'; fi
printf 'os_release_end\n'
printf 'nv_tegra_release=%s\n' "$(read_text_file /etc/nv_tegra_release)"
printf 'cmdline=%s\n' "$(read_text_file /proc/cmdline)"
printf 'root_source=%s\n' "$(findmnt -n -o SOURCE / 2>/dev/null || printf 'unavailable')"
printf 'root_fstype=%s\n' "$(findmnt -n -o FSTYPE / 2>/dev/null || printf 'unavailable')"
printf 'memory_kib=%s\n' "$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"

printf 'lsblk_begin\n'
lsblk -b -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL,ROTA,RO
printf 'lsblk_end\n'

printf 'bootctl_begin\n'
if command -v bootctl >/dev/null 2>&1; then bootctl status 2>&1 || true; else printf 'unavailable\n'; fi
printf 'bootctl_end\n'

printf 'gpu_modules_begin\n'
awk '$1 ~ /^(nvgpu|nvidia|nvidia_drm|nvidia_modeset|nvidia_uvm)$/ {print}' /proc/modules 2>/dev/null || true
printf 'gpu_modules_end\n'

printf 'pci_nvidia_begin\n'
if command -v lspci >/dev/null 2>&1; then lspci -nn | grep -i nvidia || true; else printf 'unavailable\n'; fi
printf 'pci_nvidia_end\n'

printf 'nvme_health_begin\n'
if command -v nvme >/dev/null 2>&1; then
  for controller in /dev/nvme[0-9]; do
    [[ -e "$controller" ]] || continue
    printf 'controller=%s\n' "$controller"
    nvme smart-log "$controller" 2>&1 || true
  done
else
  printf 'nvme-cli unavailable\n'
fi
printf 'nvme_health_end\n'

printf 'emmc_health_begin\n'
for emmc in /sys/block/mmcblk*/device; do
  [[ -d "$emmc" ]] || continue
  printf 'device=%s\n' "${emmc%/device}"
  for attribute in cid csd date fwrev life_time oemid preferred_erase_size pre_eol_info serial; do
    [[ -r "$emmc/$attribute" ]] || continue
    printf '%s=%s\n' "$attribute" "$(read_text_file "$emmc/$attribute")"
  done
done
printf 'emmc_health_end\n'

printf 'This report is read-only. Review it before constructing or flashing an image.\n'
