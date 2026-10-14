#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin"
export WORKSPACE_FIXTURE_LOG="$fixture_dir/hyprctl.log"

cat >"$fixture_dir/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  activeworkspace) printf '{"id":2}\n' ;;
  clients)
    if [[ ${WORKSPACE_FIXTURE_OCCUPIED:-0} == 1 ]]; then
      printf '[{"workspace":{"id":2}}]\n'
    else
      printf '[]\n'
    fi
    ;;
  dispatch) printf '%s\n' "$*" >>"$WORKSPACE_FIXTURE_LOG" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$fixture_dir/bin/hyprctl"
cat >"$fixture_dir/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture_dir/bin/notify-send"
export PATH="$fixture_dir/bin:$PATH"

menu="$repo_root/packages/omarchy-jetson-menu/omarchy-menu"
$menu list workspaces | grep -Fq $'move-workspaces\tMove active window to workspace…'
$menu list move-workspaces | grep -Fq $'move-workspace:10\tMove active window to workspace 10'

$menu action workspace:3
grep -Fxq 'dispatch workspace 3' "$WORKSPACE_FIXTURE_LOG"
$menu action move-workspace:4
grep -Fxq 'dispatch movetoworkspace 4' "$WORKSPACE_FIXTURE_LOG"
$menu action workspace-close
grep -Fxq 'dispatch workspace previous' "$WORKSPACE_FIXTURE_LOG"

before=$(wc -l <"$WORKSPACE_FIXTURE_LOG")
WORKSPACE_FIXTURE_OCCUPIED=1 $menu action workspace-close
after=$(wc -l <"$WORKSPACE_FIXTURE_LOG")
[[ $before == "$after" ]]

printf 'PASS  workspace switch, move and safe-empty-close fixture\n'
