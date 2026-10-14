#!/usr/bin/env bash
set -Eeuo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -r -- "$fixture"' EXIT
mkdir -p "$fixture/config/waybar" "$fixture/config/omarchy-jetson"
cp "$repo_root/config/rootfs/waybar-config.jsonc" "$fixture/config/waybar/config.jsonc"
printf '/* fixture */\n' >"$fixture/config/omarchy-jetson/waybar.css"
export XDG_CONFIG_HOME="$fixture/config" OMARCHY_BAR_DRY_RUN=1
bar="$repo_root/packages/omarchy-jetson-menu/omarchy-jetson-bar"

"$bar" module cpu on
jq -e '.pulseaudio.format == "{icon}" and
  .pulseaudio."tooltip-format" == "Volume {volume}%"' "$fixture/config/waybar/config.jsonc" >/dev/null
jq -e '."modules-right" | index("cpu") != null' "$fixture/config/waybar/config.jsonc" >/dev/null
"$bar" module cpu off
jq -e '."modules-right" | index("cpu") == null' "$fixture/config/waybar/config.jsonc" >/dev/null
"$bar" module clock off
jq -e '."modules-center" | index("clock") == null' "$fixture/config/waybar/config.jsonc" >/dev/null
"$bar" mode autohide
jq -e '.start_hidden == true and ."on-sigusr1" == "toggle"' "$fixture/config/waybar/config.jsonc" >/dev/null
jq -e '.mode == "autohide"' "$fixture/config/omarchy-jetson/bar.json" >/dev/null
"$bar" mode disabled
jq -e '.mode == "disabled"' "$fixture/config/omarchy-jetson/bar.json" >/dev/null
if "$bar" module unsafe on >/dev/null 2>&1; then exit 1; fi
if "$bar" mode broken >/dev/null 2>&1; then exit 1; fi
printf 'PASS  optional bar modules and visibility modes fixture\n'
