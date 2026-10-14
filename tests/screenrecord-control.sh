#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
cleanup() {
  [[ -r $fixture_dir/runtime/omarchy-jetson/screenrecord.pid ]] &&
    kill "$(<"$fixture_dir/runtime/omarchy-jetson/screenrecord.pid")" 2>/dev/null || true
  find "$fixture_dir" -depth -delete
}
trap cleanup EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/runtime" "$fixture_dir/state" "$fixture_dir/videos"
export SCREENRECORD_FIXTURE_LOG="$fixture_dir/wf-recorder.args"

cat >"$fixture_dir/bin/wf-recorder" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$SCREENRECORD_FIXTURE_LOG"
while (($#)); do
  if [[ $1 == -f ]]; then
    shift
    printf 'fixture-video\n' >"$1"
    break
  fi
  shift
done
sleep 30
EOF
cat >"$fixture_dir/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '[{"focused":true,"name":"DP-1"}]\n'
EOF
cat >"$fixture_dir/bin/omarchy-notification-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture_dir/bin/"*

export PATH="$fixture_dir/bin:$PATH"
export XDG_RUNTIME_DIR="$fixture_dir/runtime"
export XDG_STATE_HOME="$fixture_dir/state"
export XDG_VIDEOS_DIR="$fixture_dir/videos"

controller="$repo_root/packages/omarchy-jetson-actions/omarchy-capture-screenrecording"
if $controller --fullscreen --with-desktop-audio --with-microphone-audio 2>/dev/null; then
  printf 'FAIL  accepted two simultaneous audio sources\n' >&2
  exit 1
fi

$controller --fullscreen
grep -Fxq -- '-o' "$SCREENRECORD_FIXTURE_LOG"
grep -Fxq -- 'DP-1' "$SCREENRECORD_FIXTURE_LOG"
grep -Fxq -- '--no-dmabuf' "$SCREENRECORD_FIXTURE_LOG"
grep -Fxq -- 'libx264' "$SCREENRECORD_FIXTURE_LOG"
[[ -s $XDG_RUNTIME_DIR/omarchy-jetson/screenrecord.pid ]]
[[ -s $XDG_RUNTIME_DIR/omarchy-jetson/screenrecord.path ]]

printf 'PASS  bounded Jetson screen-record start fixture\n'
