#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -r -- "$fixture"' EXIT
mkdir -p "$fixture/bin"

# This literal is the generated fixture source.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\n[[ ${TERMINAL_EXPECT_FD9_CLOSED:-} != 1 || ! -e /proc/$$/fd/9 ]] || exit 90\nprintf "%%s\\n" "$*" >"$TERMINAL_FIXTURE_LOG"\n' \
  >"$fixture/bin/setsid"
chmod +x "$fixture/bin/setsid"
ln -s "$repo_root/packages/omarchy-jetson-upstream/omarchy-launch-terminal" \
  "$fixture/bin/omarchy-launch-terminal"

TERMINAL_FIXTURE_LOG="$fixture/call" PATH="$fixture/bin:/usr/bin" \
  OMARCHY_TERMINAL=foot-test \
  "$repo_root/packages/omarchy-jetson-upstream/omarchy-launch-terminal" \
  --app-id=test.terminal
grep -Fxq 'uwsm-app -- foot-test --app-id=test.terminal' "$fixture/call"

TERMINAL_FIXTURE_LOG="$fixture/call" PATH="$fixture/bin:/usr/bin" \
  OMARCHY_TERMINAL=foot-test \
  "$repo_root/packages/omarchy-jetson-upstream/omarchy-launch-terminal" \
  --title 'Model build' --header-color ff2563eb
grep -Fxq 'uwsm-app -- foot-test --title Model build --override=csd.preferred=client --override=csd.color=ff2563eb --override=csd.button-color=ffffffff --override=csd.border-width=1' "$fixture/call"

if TERMINAL_FIXTURE_LOG="$fixture/call" PATH="$fixture/bin:/usr/bin" \
  "$repo_root/packages/omarchy-jetson-upstream/omarchy-launch-terminal" \
  --header-color invalid 2>/dev/null; then
  printf 'FAIL  invalid header colour accepted\n' >&2
  exit 1
fi

context_state="$fixture/contexts.json"
OMARCHY_TERMINAL_CONTEXT_STATE="$context_state" \
  "$repo_root/packages/omarchy-jetson-upstream/omarchy-terminal-context" create 'Model build' blue
OMARCHY_TERMINAL_CONTEXT_STATE="$context_state" \
  "$repo_root/packages/omarchy-jetson-upstream/omarchy-terminal-context" create Logs amber
grep -Fxq $'Logs\tffd97706' <(
  OMARCHY_TERMINAL_CONTEXT_STATE="$context_state" \
    "$repo_root/packages/omarchy-jetson-upstream/omarchy-terminal-context" list
)
OMARCHY_TERMINAL_CONTEXT_STATE="$context_state" \
  "$repo_root/packages/omarchy-jetson-upstream/omarchy-terminal-context" delete Logs
[[ $(jq '.contexts | length' "$context_state") == 1 ]]
TERMINAL_EXPECT_FD9_CLOSED=1 TERMINAL_FIXTURE_LOG="$fixture/context-call" \
  PATH="$fixture/bin:/usr/bin" OMARCHY_TERMINAL=foot-test \
  OMARCHY_TERMINAL_CONTEXT_STATE="$context_state" \
  "$repo_root/packages/omarchy-jetson-upstream/omarchy-terminal-context" open 'Model build'
grep -Fq -- '--title Model build --override=csd.preferred=client' "$fixture/context-call"
grep -Fq -- '--app-id omarchy-terminal-ff2563eb' "$fixture/context-call"

printf 'PASS  Foot/UWSM launcher and persistent named-colour context fixture\n'
