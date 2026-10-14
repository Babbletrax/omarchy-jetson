#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/home" "$fixture_dir/run"
export SESSION_FIXTURE_LOG="$fixture_dir/calls.log"
# Keep the scripts off the real user state (stay-awake indicator, etc.).
export XDG_STATE_HOME="$fixture_dir/home/.local/state"

python - "$repo_root/config/rootfs/greetd-config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as stream:
    config = tomllib.load(stream)
expected = "uwsm start -e -D Hyprland hyprland.desktop"
assert "initial_session" not in config, "autologin must not name a site-specific user"
assert expected in config["default_session"]["command"]
PY
grep -Fxq 'ExecStart=/usr/bin/greetd --config /etc/greetd/omarchy-jetson.toml' \
  "$repo_root/packages/omarchy-jetson-session/greetd-override.conf"
grep -Fxq '  systemctl enable greetd.service' \
  "$repo_root/packages/omarchy-jetson-session/omarchy-jetson-session.install"

for command in hyprctl logger; do
  ln -s /usr/bin/true "$fixture_dir/bin/$command"
done

# omarchy-system-lock is upstream's (the shell's lock screen) since the move to
# upstream Omarchy; only the Jetson idle-lock wrapper below is tested here.

# Upstream's toggle: a pinned checkout on the development host, else the copy
# installed by the `omarchy` package on the target.
toggle="$repo_root/artifacts/omarchy-upstream/bin/omarchy-toggle-idle"
[[ -x $toggle ]] || toggle=/usr/share/omarchy/bin/omarchy-toggle-idle
# A recording stand-in for the lock command shows whether idle-lock fired.
# This literal is the generated fixture source.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'printf "lock\n" >>"$SESSION_FIXTURE_LOG"' \
  >"$fixture_dir/bin/omarchy-system-lock"
chmod +x "$fixture_dir/bin/omarchy-system-lock"

# Stay-awake: the idle timeout must not lock.
: >"$SESSION_FIXTURE_LOG"
HOME="$fixture_dir/home" "$toggle" stay-awake | grep -Fxq disabled
HOME="$fixture_dir/home" PATH="$fixture_dir/bin:/usr/bin" \
  "$repo_root/packages/omarchy-jetson-session/omarchy-jetson-idle-lock"
[[ ! -s $SESSION_FIXTURE_LOG ]]

# Idle allowed: the idle timeout locks through omarchy-system-lock.
HOME="$fixture_dir/home" "$toggle" allow-idle | grep -Fxq enabled
HOME="$fixture_dir/home" PATH="$fixture_dir/bin:/usr/bin" \
  "$repo_root/packages/omarchy-jetson-session/omarchy-jetson-idle-lock"
grep -Fxq lock "$SESSION_FIXTURE_LOG"

printf 'PASS  idle-lock calls the lock only when idle is allowed\n'
