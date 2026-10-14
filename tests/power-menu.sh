#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin"
export POWER_FIXTURE_LOG="$fixture_dir/calls.log"

printf '%s\n' \
  '< POWER_MODEL ID=0 NAME=MAXN >' \
  'CPU_ONLINE CORE_0 1' \
  'GPU MAX_FREQ -1' \
  'EMC MAX_FREQ -1' \
  '< POWER_MODEL ID=2 NAME=MODE_30W >' \
  'CPU_ONLINE CORE_0 1' \
  'GPU MAX_FREQ 612000000' \
  'EMC MAX_FREQ -1' \
  '< PM_CONFIG DEFAULT=2 >' >"$fixture_dir/nvpmodel.conf"

# These literals are the generated fixture source.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' '[[ ${1:-} == -n ]] && shift' 'exec "$@"' >"$fixture_dir/bin/sudo"
# These literals are the generated fixture source.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
  'if [[ $1 == -q ]]; then printf "NV Power Mode: MODE_30W\n2\n"; else printf "%s\n" "$*" >>"$POWER_FIXTURE_LOG"; fi' \
  >"$fixture_dir/bin/nvpmodel"
for command in logger notify-send; do ln -s /usr/bin/true "$fixture_dir/bin/$command"; done
chmod +x "$fixture_dir/bin/sudo" "$fixture_dir/bin/nvpmodel"

power="$repo_root/packages/omarchy-jetson-menu/omarchy-jetson-power"
status_output=$(env PATH="$fixture_dir/bin:/usr/bin" OMARCHY_NVP_CONFIG="$fixture_dir/nvpmodel.conf" \
  OMARCHY_NVPMODEL="$fixture_dir/bin/nvpmodel" "$power" status)
grep -Fq 'GPU 612 MHz' <<<"$status_output"
if env PATH="$fixture_dir/bin:/usr/bin" OMARCHY_NVP_CONFIG="$fixture_dir/nvpmodel.conf" \
  OMARCHY_NVPMODEL="$fixture_dir/bin/nvpmodel" "$power" apply 2 2>/dev/null; then exit 1; fi
[[ ! -e $POWER_FIXTURE_LOG ]]
env PATH="$fixture_dir/bin:/usr/bin" OMARCHY_NVP_CONFIG="$fixture_dir/nvpmodel.conf" \
  OMARCHY_NVPMODEL="$fixture_dir/bin/nvpmodel" "$power" apply 2 --confirmed
grep -Fxq -- '-m 2' "$POWER_FIXTURE_LOG"

printf 'PASS  guarded NVIDIA power-mode fixture\n'
