#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

mkdir -p "$fixture_dir/bin" "$fixture_dir/config" "$fixture_dir/themes/dark" "$fixture_dir/themes/light"
cp "$repo_root/packages/omarchy-jetson-menu/theme-dark-waybar.css" "$fixture_dir/themes/dark/waybar.css"
cp "$repo_root/packages/omarchy-jetson-menu/theme-light-waybar.css" "$fixture_dir/themes/light/waybar.css"

cat >"$fixture_dir/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$APPEARANCE_FIXTURE_LOG"
if [[ $* == 'monitors -j' ]]; then
  printf '%s\n' '[{"name":"DP-1"}]'
  exit 0
fi
printf 'ok\n'
EOF
cat >"$fixture_dir/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == writable ]] && printf 'false\n'
EOF
chmod +x "$fixture_dir/bin/hyprctl"
chmod +x "$fixture_dir/bin/gsettings"

export APPEARANCE_FIXTURE_LOG="$fixture_dir/hyprctl.log"
export PATH="$fixture_dir/bin:$PATH"
export XDG_CONFIG_HOME="$fixture_dir/config"
export XDG_STATE_HOME="$fixture_dir/state"
export OMARCHY_THEME_ROOT="$fixture_dir/themes"
# A 1x1 PNG stands in for the theme's background.
base64 -d >"$fixture_dir/background.png" <<<'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
export OMARCHY_DEFAULT_BACKGROUND="$fixture_dir/background.png"
export OMARCHY_APPEARANCE_DRY_RUN=1

controller="$repo_root/packages/omarchy-jetson-menu/omarchy-jetson-appearance"
$controller set-theme light
$controller set-ui-scale 1.25
$controller set-bar-text-size 12
$controller set-font-family 'Noto Sans'

jq -e '.theme == "light" and .ui_scale == "1.25" and
  .bar_text_size == "12" and .font_family == "Noto Sans"' \
  "$XDG_CONFIG_HOME/omarchy-jetson/appearance.json" >/dev/null
grep -Fq 'font-size: 12px' "$XDG_CONFIG_HOME/omarchy-jetson/waybar.css"
grep -Fq 'font-family: "Noto Sans"' "$XDG_CONFIG_HOME/omarchy-jetson/waybar.css"
grep -Fq '#workspaces:hover button' "$XDG_CONFIG_HOME/omarchy-jetson/waybar.css"
grep -Fq 'background=f8fafcf5' "$XDG_CONFIG_HOME/omarchy-jetson/fuzzel.ini"
grep -Fq 'active_border = "rgba(2563ebee)"' "$APPEARANCE_FIXTURE_LOG"
# The wallpaper is the omarchy.background shell plugin's, as upstream has it.
# The controller's whole job is to point the state link at the image; a second
# renderer here would be a competing source of truth.
background_link="$XDG_STATE_HOME/omarchy/current/background"
[[ -L $background_link ]]
[[ $(readlink "$background_link") == "$OMARCHY_DEFAULT_BACKGROUND" ]]
if grep -Fq 'hyprpaper' "$APPEARANCE_FIXTURE_LOG"; then
  printf 'FAIL  appearance controller still drives a second wallpaper renderer\n' >&2
  exit 1
fi

if $controller set-theme third-theme 2>/dev/null; then
  printf 'FAIL  accepted an unsupported third theme\n' >&2
  exit 1
fi

printf 'PASS  two-theme appearance, bar typography and single-owner wallpaper fixture\n'
