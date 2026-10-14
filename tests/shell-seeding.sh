#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

launcher="$repo_root/packages/omarchy-jetson-upstream/omarchy-jetson-shell"

# Exercise seed_config in isolation: sourcing the launcher would start a shell,
# so lift the function out and run it against a fixture tree.
{
  sed -n '/^seed_file()/,/^}/p' "$launcher"
  sed -n '/^ensure_config()/,/^}/p' "$launcher"
} >"$fixture_dir/seed.sh"
[[ -s $fixture_dir/seed.sh ]]

export OMARCHY_SEED_ROOT="$fixture_dir/root"
export XDG_CONFIG_HOME="$fixture_dir/config"
mkdir -p "$OMARCHY_SEED_ROOT"
printf '{}\n' >"$OMARCHY_SEED_ROOT/default-shell.json"

run_seed() {
  bash -c '
    set -euo pipefail
    shell_root="$OMARCHY_SEED_ROOT"
    jetson_data="$OMARCHY_SEED_ROOT"
    shell_config="$XDG_CONFIG_HOME/omarchy/shell.json"
    menu_extension="$XDG_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
    log() { printf "%s\n" "$*"; }
    source "$1"
    ensure_config
  ' _ "$fixture_dir/seed.sh"
}

packaged="$OMARCHY_SEED_ROOT/default-menu-extension.jsonc"
extension="$XDG_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"

printf '{"items":{"a":1}}\n' >"$packaged"
out=$(run_seed)
[[ $out == *event=menu-extension-created* ]]
[[ $(<"$extension") == '{"items":{"a":1}}' ]]

# A second start must not rewrite an already-current copy: the branch is
# silent, so assert on the captured output rather than grep -v, which would
# also "pass" on no output at all.
second=$(run_seed)
[[ $second != *menu-extension-created* ]]
[[ $second != *menu-extension-refreshed* ]]

# A package upgrade refreshes a copy the user never touched, which is what
# keeps newly added menu entries from silently never appearing.
printf '{"items":{"a":2}}\n' >"$packaged"
out=$(run_seed)
[[ $out == *event=menu-extension-refreshed* ]]
[[ $(<"$extension") == '{"items":{"a":2}}' ]]

# A copy the user has edited is left alone even when the package moves on.
printf '{"items":{"mine":true}}\n' >"$extension"
printf '{"items":{"a":3}}\n' >"$packaged"
out=$(run_seed)
[[ $out == *event=menu-extension-kept-user-copy* ]]
[[ $(<"$extension") == '{"items":{"mine":true}}' ]]

# shell.json goes through the same helper, so the splash fix (enabling the
# background plugin) actually reaches an existing install on upgrade instead of
# being seeded once and never revisited.
shell_packaged="$OMARCHY_SEED_ROOT/default-shell.json"
shell_target="$XDG_CONFIG_HOME/omarchy/shell.json"
[[ $(<"$shell_target") == '{}' ]]
printf '{"disabledPlugins":[]}\n' >"$shell_packaged"
out=$(run_seed)
[[ $out == *event=config-refreshed* ]]
[[ $(<"$shell_target") == '{"disabledPlugins":[]}' ]]

printf '{"mine":true}\n' >"$shell_target"
printf '{"disabledPlugins":["x"]}\n' >"$shell_packaged"
out=$(run_seed)
[[ $out == *event=config-kept-user-copy* ]]
[[ $(<"$shell_target") == '{"mine":true}' ]]

printf 'PASS  shell.json and menu extension seeding, upgrade refresh and user-edit preservation fixture\n'
