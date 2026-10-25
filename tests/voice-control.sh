#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/run/voxtype"
calls="$fixture_dir/calls.log"
printf 'idle\n' >"$fixture_dir/run/voxtype/state"

cat >"$fixture_dir/bin/voxtype" <<'EOF'
#!/usr/bin/env bash
printf 'voxtype %s\n' "$*" >>"$VOICE_FIXTURE_CALLS"
if [[ $1 == status ]]; then
  cat "$OMARCHY_VOICE_STATE_FILE"
elif [[ $1 == config && $2 == get ]]; then
  case $3 in
    hotkey.enabled|output.auto_submit|text.smart_auto_submit) value=false ;;
    output.mode) value=type ;;
    *) exit 2 ;;
  esac
  printf '{"value":%s}\n' "$([[ $value == false ]] && printf false || printf '"%s"' "$value")"
fi
EOF
cat >"$fixture_dir/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$VOICE_FIXTURE_CALLS"
if [[ $* == *is-active* ]]; then
  printf 'active\n'
fi
EOF
ln -s /usr/bin/true "$fixture_dir/bin/wtype"
chmod +x "$fixture_dir/bin/voxtype" "$fixture_dir/bin/systemctl"

export PATH="$fixture_dir/bin:/usr/bin"
export VOICE_FIXTURE_CALLS="$calls"
export OMARCHY_VOXTYPE_COMMAND="$fixture_dir/bin/voxtype"
export OMARCHY_VOICE_SYSTEMCTL="$fixture_dir/bin/systemctl"
export OMARCHY_VOICE_STATE_FILE="$fixture_dir/run/voxtype/state"
controller="$repo_root/packages/omarchy-jetson-voice/omarchy-voice-control"
hyprland_config="$repo_root/config/rootfs/hyprland.lua"

if rg -n 'hl\.exec_cmd\("voxtype daemon' "$hyprland_config"; then
  printf 'FAIL Hyprland still starts an unmanaged Voxtype daemon\n' >&2
  exit 1
fi
grep -Fq 'o.bind("SUPER + CTRL + F9", "Cancel dictation", "omarchy-voice-control cancel")' "$hyprland_config"

# Capture first: grep -q stops reading at the first match, and with pipefail the
# writer's SIGPIPE (141) would fail the test intermittently.
doctor_out=$($controller doctor)
grep -Fq 'PASS  text.smart_auto_submit=false' <<<"$doctor_out"
$controller start
$controller stop
$controller cancel
$controller recover >/dev/null
grep -Fxq 'voxtype record start' "$calls"
grep -Fxq 'voxtype record stop' "$calls"
grep -Fxq 'voxtype record cancel' "$calls"
grep -Fxq 'systemctl --user restart voxtype.service' "$calls"

if $controller invalid >/dev/null 2>&1; then
  printf 'FAIL invalid voice-control command was accepted\n' >&2
  exit 1
fi

printf 'PASS  voice safety, cancellation and recovery fixture\n'
