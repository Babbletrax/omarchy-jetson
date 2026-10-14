#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

mkdir -p "$fixture_dir/bin" "$fixture_dir/config"
export DISPLAY_FIXTURE_LOG="$fixture_dir/eval.log"
export DISPLAY_FIXTURE_STATE="$fixture_dir/mode.state"
# Modes the fixture sink can actually drive. Anything else is accepted by
# hyprctl and then quietly ignored, which is how a real display behaves when
# asked for a mode beyond its EDID.
export DISPLAY_FIXTURE_SUPPORTED="800x480 1920x1080"
printf '800 480 60.004\n' >"$DISPLAY_FIXTURE_STATE"

cat >"$fixture_dir/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
read -r width height refresh <"$DISPLAY_FIXTURE_STATE"
if [[ ${1:-} == monitors && ${2:-} == all && ${3:-} == -j ]]; then
  printf '[{"name":"DP-1","description":"Fixture monitor","disabled":false,"width":%s,"height":%s,"refreshRate":%s,"x":0,"y":0,"scale":1,"availableModes":["800x480@50.00Hz","800x480@60.00Hz","1920x1080@59.94Hz"]}]\n' \
    "$width" "$height" "$refresh"
elif [[ ${1:-} == eval ]]; then
  printf '%s\n' "$2" >>"$DISPLAY_FIXTURE_LOG"
  if [[ $2 =~ mode\ =\ \"([0-9]+)x([0-9]+)@([0-9.]+) ]]; then
    requested="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
    for supported in $DISPLAY_FIXTURE_SUPPORTED; do
      if [[ $requested == "$supported" ]]; then
        printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
          >"$DISPLAY_FIXTURE_STATE"
        break
      fi
    done
  fi
  printf 'ok\n'
else
  exit 2
fi
EOF

cat >"$fixture_dir/bin/fuzzel" <<'EOF'
#!/usr/bin/env bash
if [[ ${DISPLAY_FIXTURE_CONFIRM:-} == keep ]]; then
  printf 'keep\n'
  exit 0
fi
exit 1
EOF

chmod +x "$fixture_dir/bin/hyprctl" "$fixture_dir/bin/fuzzel"
export PATH="$fixture_dir/bin:$PATH"
export XDG_CONFIG_HOME="$fixture_dir/config"

controller="$repo_root/packages/omarchy-jetson-menu/omarchy-jetson-display"
expected=$'DP-1\t800x480@60.00Hz\t0x0\t1'
actual=$($controller current DP-1)
[[ $actual == "$expected" ]]

# An unconfirmed change rolls back to the mode that was active before it.
$controller set DP-1 1920x1080@59.94Hz 0x0 1
[[ $(wc -l <"$DISPLAY_FIXTURE_LOG") == 2 ]]
grep -Fq 'mode = "1920x1080@59.94Hz"' "$DISPLAY_FIXTURE_LOG"
tail -n 1 "$DISPLAY_FIXTURE_LOG" | grep -Fq 'mode = "800x480@60.00Hz"'

DISPLAY_FIXTURE_CONFIRM=keep $controller set DP-1 1920x1080@59.94Hz 0x0 1
expected_saved=$'DP-1\t1920x1080@59.94Hz\t0x0\t1'
actual_saved=$(<"$XDG_CONFIG_HOME/omarchy-jetson/displays/DP-1.tsv")
[[ $actual_saved == "$expected_saved" ]]

# A mode outside the EDID list is attempted rather than refused up front, so a
# 4K or ultra-wide panel is reachable even when the current sink caps lower.
: >"$DISPLAY_FIXTURE_LOG"
if DISPLAY_FIXTURE_CONFIRM=keep $controller set DP-1 3840x2160@60.00Hz 0x0 1 2>"$fixture_dir/err"; then
  printf 'FAIL  a mode the sink refused was reported as applied\n' >&2
  exit 1
fi
grep -Fq 'mode = "3840x2160@60.00Hz"' "$DISPLAY_FIXTURE_LOG"

# ...and when the sink quietly ignores it, that is surfaced rather than passing
# silently, with the previously saved mode left untouched.
grep -Fq 'display-rejected-mode' "$fixture_dir/err"
grep -Fq 'requested=3840x2160' "$fixture_dir/err"
still_saved=$(<"$XDG_CONFIG_HOME/omarchy-jetson/displays/DP-1.tsv")
[[ $still_saved == "$expected_saved" ]]

# The menu offers the large presets alongside whatever the display advertises.
offered=$(sed -n 's/^  .\(3840x2160@60.00Hz\|3440x1440@60.00Hz\|2560x1080@60.00Hz\).*/\1/p' "$controller" | wc -l)
[[ $offered == 3 ]]

# Upstream's scaling ladder includes 1.6 and range-checks 1..4, so a scale it
# can set must be representable here too, or the value the user chose cannot be
# saved at all.
DISPLAY_FIXTURE_CONFIRM=keep $controller set DP-1 1920x1080@59.94Hz 0x0 1.6
saved_scale=$(cut -f4 "$XDG_CONFIG_HOME/omarchy-jetson/displays/DP-1.tsv")
[[ $saved_scale == 1.6 ]]

if $controller set DP-1 1920x1080@59.94Hz 0x0 5 2>"$fixture_dir/scale-err"; then
  printf 'FAIL  a scale outside the supported range was accepted\n' >&2
  exit 1
fi
grep -Fq 'invalid-scale=5' "$fixture_dir/scale-err"

# save-current records whatever is live. This is what makes a scale change made
# outside this controller survive a reboot, since apply-saved is what reapplies
# display state at session start.
printf '1920 1080 59.94\n' >"$DISPLAY_FIXTURE_STATE"
printf 'DP-1\t800x480@60.00Hz\t0x0\t1\n' >"$XDG_CONFIG_HOME/omarchy-jetson/displays/DP-1.tsv"
$controller save-current DP-1
recorded=$(<"$XDG_CONFIG_HOME/omarchy-jetson/displays/DP-1.tsv")
[[ $recorded == $'DP-1\t1920x1080@59.94Hz\t0x0\t1' ]]

printf 'PASS  display normalization, rollback, large-mode presets, scale range and save-current fixture\n'
