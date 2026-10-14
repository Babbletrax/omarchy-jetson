#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

mkdir -p "$fixture_dir/bin" "$fixture_dir/config"

# The controller reads the effect list from ttfx itself so that a ttfx upgrade
# cannot leave the menu offering an effect that no longer runs.
cat >"$fixture_dir/bin/ttfx" <<'EOF'
#!/usr/bin/env bash
cat <<'HELP'
Terminal text effects

Usage: ttfx [OPTIONS] [COMMAND]

Commands:
  beams   Create beams
  matrix  Matrix digital rain effect
  rain    Rain characters
  help    Print this message

Options:
  -i <FILE>
HELP
EOF

cat >"$fixture_dir/bin/fuzzel" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
[[ -n ${SCREENSAVER_FIXTURE_PICK:-} ]] || exit 1
printf '%s\n' "$SCREENSAVER_FIXTURE_PICK"
EOF

chmod +x "$fixture_dir/bin/ttfx" "$fixture_dir/bin/fuzzel"
export PATH="$fixture_dir/bin:$PATH"
export XDG_CONFIG_HOME="$fixture_dir/config"

controller="$repo_root/packages/omarchy-jetson-menu/omarchy-jetson-screensaver"
state="$XDG_CONFIG_HOME/omarchy-jetson/screensaver-effect"

# Effects come from ttfx, excluding its own help subcommand.
[[ $($controller list | tr '\n' ' ') == 'beams matrix rain ' ]]

# With nothing chosen the stock random behaviour is preserved.
[[ $($controller show) == random ]]
[[ $($controller effect-args) == '--random-effect' ]]

# A chosen effect is passed to ttfx as its subcommand instead.
$controller set matrix >/dev/null
[[ $(<"$state") == matrix ]]
[[ $($controller show) == matrix ]]
[[ $($controller effect-args) == matrix ]]

# Selecting through the menu persists the pick.
SCREENSAVER_FIXTURE_PICK=rain $controller select
[[ $($controller effect-args) == rain ]]

# Returning to random restores the upstream flag.
$controller set random >/dev/null
[[ $($controller effect-args) == '--random-effect' ]]

# An effect ttfx does not provide is refused rather than written to state.
if $controller set nonsuch 2>"$fixture_dir/err"; then
  printf 'FAIL  unknown effect was accepted\n' >&2
  exit 1
fi
grep -Fq 'unknown-effect=nonsuch' "$fixture_dir/err"
[[ $(<"$state") == random ]]

# State that no longer names a valid effect degrades to random rather than
# handing ttfx a subcommand it will reject.
printf 'retired-effect\n' >"$state"
[[ $($controller show) == random ]]
[[ $($controller effect-args) == '--random-effect' ]]

# The packaged menu exposes selection, and upstream's runner consumes it.
extension="$repo_root/packages/omarchy-jetson-upstream/default-menu-extension.jsonc"
grep -Fq '"style.screensaver.effect"' "$extension"
grep -Fq 'omarchy-jetson-screensaver select' "$extension"
grep -Fq 'omarchy-jetson-screensaver preview' "$extension"
grep -Fq 'omarchy-jetson-screensaver effect-args' \
  "$repo_root/packages/omarchy-jetson-upstream/PKGBUILD"

printf 'PASS  screensaver effect selection, fallback and menu wiring fixture\n'
