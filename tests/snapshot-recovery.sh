#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
cleanup() { chmod -R u+w "$fixture" 2>/dev/null || true; find "$fixture" -depth -delete; }
trap cleanup EXIT
mkdir -p "$fixture/source/etc" "$fixture/restore"
printf '%s\n' original >"$fixture/source/etc/value"
printf '%s\n' unchanged >"$fixture/source/etc/stable"
snapshot=$repo_root/packages/omarchy-jetson-recovery/omarchy-jetson-snapshot
export OMARCHY_SNAPSHOT_ROOT=$fixture/snapshots
export OMARCHY_SNAPSHOT_SOURCE=$fixture/source
export OMARCHY_SNAPSHOT_TESTING=true

"$snapshot" create before >/dev/null
first_inode=$(stat -c %i "$fixture/snapshots/before/root/etc/stable")
printf '%s\n' changed >"$fixture/source/etc/value"
"$snapshot" create after >/dev/null
second_inode=$(stat -c %i "$fixture/snapshots/after/root/etc/stable")
[[ $first_inode == "$second_inode" ]]
printf '%s\n' extra >"$fixture/restore/extra"
touch "$fixture/restore/.omarchy-jetson-restore-target"
"$snapshot" restore before "$fixture/restore" --confirmed >/dev/null
grep -Fxq original "$fixture/restore/etc/value"
[[ ! -e $fixture/restore/extra ]]
[[ $("$snapshot" list | wc -l) == 2 ]]
printf '%s\n' corrupt >"$fixture/snapshots/after/root/etc/value"
touch "$fixture/restore/.omarchy-jetson-restore-target"
if "$snapshot" restore after "$fixture/restore" --confirmed >/dev/null 2>&1; then exit 1; fi
if "$snapshot" restore before / --confirmed >/dev/null 2>&1; then exit 1; fi
printf '%s\n' 'PASS  incremental snapshot and guarded offline rollback fixture'
