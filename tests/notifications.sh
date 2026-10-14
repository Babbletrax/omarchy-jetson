#!/usr/bin/env bash
set -Eeuo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -r -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/config"
# This literal is the generated fixture source.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "systemctl %%s\\n" "$*" >>"$CALLS"\n' >"$fixture/bin/systemctl"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$CALLS"\n[[ $* == *count* ]] && printf "2\\n"\n[[ $* == *get-dnd* ]] && printf "false\\n"\nexit 0\n' >"$fixture/bin/swaync-client"
chmod +x "$fixture/bin/swaync-client"
chmod +x "$fixture/bin/systemctl"
export PATH="$fixture/bin:/usr/bin" CALLS="$fixture/calls" XDG_CONFIG_HOME="$fixture/config"
export OMARCHY_NOTIFICATION_DEFAULTS="$repo_root/packages/omarchy-jetson-notifications"
control="$repo_root/packages/omarchy-jetson-notifications/omarchy-notification-center"
"$control" start
"$control" timeout 30
jq -e '.timeout == 30 and ."timeout-low" == 5' "$fixture/config/swaync/config.json" >/dev/null
"$control" mark-unread
"$control" read-all
grep -Fxq -- '--hide-all' "$CALLS"
grep -Fxq -- '--close-all' "$CALLS"
grep -Fxq 'systemctl --user start swaync.service' "$CALLS"
if "$control" timeout 7 >/dev/null 2>&1; then exit 1; fi
printf 'PASS  notification acknowledgement and timeout fixture\n'
