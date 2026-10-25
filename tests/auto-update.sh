#!/usr/bin/env bash
# Fixture test for omarchy-jetson-updates: the settings command, the check and
# apply gates, the kernel/BSP block and the preserved configuration. Every
# system command is a fake on PATH; nothing here touches the host.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pkg=$repo_root/packages/omarchy-jetson-updates
settings=$pkg/omarchy-jetson-update-settings
backend=$pkg/omarchy-jetson-auto-update
notify=$pkg/omarchy-jetson-update-notify

fixture=$(mktemp -d)
trap 'rm -r -- "$fixture"' EXIT
bin=$fixture/bin
mkdir -p "$bin"

fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

fake() { # name, body
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$bin/$1"
  chmod +x "$bin/$1"
}

# The fake bodies are literal script source.
# shellcheck disable=SC2016
{
  fake systemctl 'printf "systemctl %s\n" "$*" >>"$CALLS"'
  fake sudo 'printf "sudo %s\n" "$*" >>"$CALLS"; exit 1'
  fake checkupdates '
    printf "checkupdates %s\n" "$*" >>"$CALLS"
    [[ $* == *--download* ]] && exit 0
    rc=${FAKE_CHECK_RC:-0}
    ((rc == 0)) && cat "$FAKE_UPDATES"
    exit "$rc"'
  fake nmcli 'printf "%s\n" "${FAKE_CONNECTIVITY:-full}"'
  fake df 'printf "Avail\n%s\n" "${FAKE_AVAIL_KIB:-9999999}"'
  fake pacman-conf 'printf "%s\n" ${FAKE_IGNORED-linux-aarch64 linux-aarch64-headers}'
  fake loginctl '
    if [[ $1 == list-sessions ]]; then
      awk "{ print \$1, 1000, \"user\" }" "$FAKE_SESSIONS"
      exit 0
    fi
    id=$2 prop=$4
    awk -v id="$id" -v prop="$prop" "\$1 == id {
      if (prop == \"Type\") print \$2; if (prop == \"Class\") print \$3
      if (prop == \"IdleHint\") print \$4; if (prop == \"LockedHint\") print \$5 }" "$FAKE_SESSIONS"'
  fake omarchy-update-lock 'printf "omarchy-update-lock %s\n" "$1" >>"$CALLS"; shift; exec "$@"'
  fake omarchy-update-pkg-prune 'printf "omarchy-update-pkg-prune\n" >>"$CALLS"'
  fake omarchy-update-keyring 'printf "omarchy-update-keyring\n" >>"$CALLS"'
  fake omarchy-snapshot 'printf "omarchy-snapshot %s\n" "$*" >>"$CALLS"; exit 127'
  fake omarchy-update-system-pkgs '
    printf "omarchy-update-system-pkgs unattended=%s path=%s\n" "${OMARCHY_UPDATE_UNATTENDED:-}" "${OMARCHY_PATH:-}" >>"$CALLS"
    exit "${FAKE_SYSPKGS_RC:-0}"'
  fake omarchy-notification-send 'printf "notify %s\n" "$*" >>"$CALLS"'
  fake omarchy-notification-wait 'exit 0'
  fake omarchy-migrate-notify 'printf "omarchy-migrate-notify\n" >>"$CALLS"'
}

export PATH="$bin:/usr/bin:/bin"
export CALLS=$fixture/calls
export OMARCHY_JETSON_UPDATE_CONF=$fixture/etc/omarchy-jetson/auto-update.conf
export OMARCHY_JETSON_UPDATE_STATE=$fixture/state
export OMARCHY_JETSON_UPDATE_LOG=$fixture/auto-update.log
export OMARCHY_JETSON_UPDATE_UNIT_DIR=$fixture/systemd
export OMARCHY_JETSON_PACMAN_LOCK=$fixture/db.lck
export OMARCHY_JETSON_PACMAN_CONF=$fixture/pacman.conf
export OMARCHY_JETSON_KERNEL_BACKUP_HOOK=$fixture/no-kernel-backup.hook
export OMARCHY_JETSON_UPSTREAM_LOCKS="$fixture/run/*/omarchy-update.lock"
export XDG_STATE_HOME=$fixture/user-state
export FAKE_UPDATES=$fixture/updates FAKE_SESSIONS=$fixture/sessions
dropin=$fixture/systemd/omarchy-jetson-update-check.timer.d/10-time.conf
pending=$fixture/state/auto-pending
notice=$fixture/state/notices/auto-update

mkdir -p "$(dirname "$OMARCHY_JETSON_UPDATE_CONF")"
cp "$pkg/auto-update.conf" "$OMARCHY_JETSON_UPDATE_CONF"

# --- settings: defaults and --show ------------------------------------------
show=$("$settings" --show)
grep -Fxq 'automatic=off' <<<"$show" || fail "default is not off: $show"
grep -Fxq 'time=03:00' <<<"$show" || fail "default time is not 03:00: $show"
grep -Fxq 'pending=0' <<<"$show" || fail "pending count: $show"
grep -Fxq 'enabled=no' "$pkg/auto-update.conf" || fail 'packaged config is not off by default'
pass 'settings default to off at 03:00'

# --- settings: --time validation --------------------------------------------
for bad in 3:00 24:00 12:60 1200 12:00:00 'ab:cd' '' ' 03:00' $'03:00\nOnCalendar=minutely' '03:00;reboot'; do
  if "$settings" --time "$bad" >/dev/null 2>&1; then fail "accepted bad time '$bad'"; fi
done
[[ ! -e $dropin ]] || fail 'a rejected time wrote a drop-in'
[[ ! -e $CALLS ]] || fail 'a rejected time called something'
for bad in '--auto maybe' '--auto' '--bogus' '--time 03:00 extra' '--show extra'; do
  # shellcheck disable=SC2086 # split on purpose
  if "$settings" $bad >/dev/null 2>&1; then fail "accepted '$bad'"; fi
done
pass 'settings reject malformed times and arguments'

# --- settings: --time drop-in contents and idempotence ----------------------
"$settings" --time 04:30 >/dev/null
expected=$(printf '%s\n' '# Written by omarchy-jetson-update-settings --time.' '[Timer]' 'OnCalendar=' \
  'OnCalendar=*-*-* 04:30:00' 'RandomizedDelaySec=10min' 'Persistent=true')
[[ $(<"$dropin") == "$expected" ]] || fail "drop-in contents: $(<"$dropin")"
grep -Fxq 'systemctl daemon-reload' "$CALLS" || fail 'no daemon-reload'
grep -Fxq 'systemctl restart omarchy-jetson-update-check.timer' "$CALLS" || fail 'timer not restarted'
[[ $("$settings" --show | grep '^time=') == time=04:30 ]] || fail '--show does not report the new time'
: >"$CALLS"
"$settings" --time 04:30 >/dev/null
[[ $(<"$dropin") == "$expected" ]] || fail 'second identical --time changed the drop-in'
[[ ! -s $CALLS ]] || fail "identical --time reloaded systemd: $(<"$CALLS")"
"$settings" --time 23:59 >/dev/null
grep -Fxq 'OnCalendar=*-*-* 23:59:00' "$dropin" || fail 'time change not written'
[[ $(grep -c '^OnCalendar=' "$dropin") == 2 ]] || fail 'drop-in must reset OnCalendar then set one time'
! grep -q sudo "$CALLS" || fail 'writable paths must not go through sudo'
pass 'settings --time writes an idempotent timer drop-in'

# --- settings: --auto on/off keeps the rest of the config --------------------
printf '# local note kept\ncustom=value\n' >>"$OMARCHY_JETSON_UPDATE_CONF"
before_other=$(grep -v '^enabled=' "$OMARCHY_JETSON_UPDATE_CONF")
"$settings" --auto on >/dev/null
grep -Fxq 'enabled=yes' "$OMARCHY_JETSON_UPDATE_CONF" || fail 'auto on not written'
[[ $(grep -c '^enabled=' "$OMARCHY_JETSON_UPDATE_CONF") == 1 ]] || fail 'duplicate enabled= lines'
[[ $(grep -v '^enabled=' "$OMARCHY_JETSON_UPDATE_CONF") == "$before_other" ]] || fail 'auto on dropped other config lines'
"$settings" --auto on >/dev/null
[[ $(grep -c '^enabled=' "$OMARCHY_JETSON_UPDATE_CONF") == 1 ]] || fail '--auto on is not idempotent'
[[ $("$settings" --show | grep '^automatic=') == automatic=on ]] || fail '--show does not report on'
[[ ! -e $pending ]] || fail 'auto on without known updates marked pending'
"$settings" --auto off >/dev/null
grep -Fxq 'enabled=no' "$OMARCHY_JETSON_UPDATE_CONF" || fail 'auto off not written'
[[ $(grep -v '^enabled=' "$OMARCHY_JETSON_UPDATE_CONF") == "$before_other" ]] || fail 'auto off dropped other config lines'
pass 'settings --auto on|off is idempotent and preserves the config file'

# --- package: config preserved across upgrades -------------------------------
pkgbuild=$pkg/PKGBUILD
grep -Fxq "backup=('etc/omarchy-jetson/auto-update.conf')" "$pkgbuild" || fail 'config is not in backup='
# shellcheck disable=SC2016 # a literal PKGBUILD line
grep -Fq '"$pkgdir/etc/omarchy-jetson/auto-update.conf"' "$pkgbuild" || fail 'config not installed at its backup path'
! grep -Eq 'etc/hostname' "$pkgbuild" "$backend" "$settings" || fail 'updates must never touch /etc/hostname'
grep -Fq 'OnCalendar=*-*-* 03:00:00' "$pkg/omarchy-jetson-update-check.timer" || fail 'timer default is not 03:00'
grep -Fq 'Persistent=true' "$pkg/omarchy-jetson-update-check.timer" || fail 'timer is not persistent'
grep -Fq 'ConditionPathExists=/var/lib/omarchy-jetson/updates/auto-pending' "$pkg/omarchy-jetson-auto-update.service" ||
  fail 'apply service is not gated on the pending marker'
pass 'package keeps the config file across upgrades'

# --- check: list, pre-download and pending marker ---------------------------
printf 'mesa 1.0-1 -> 1.1-1\nlinux-aarch64 6.1-1 -> 6.2-1 [ignored]\n' >"$FAKE_UPDATES"
printf '2 wayland user yes no\n' >"$FAKE_SESSIONS"
: >"$CALLS"
"$backend" check
grep -Fxq 'checkupdates --nosync --download' "$CALLS" || fail 'check did not pre-download'
[[ ! -e $pending ]] || fail 'check marked pending while automatic updates are off'
[[ $("$settings" --show | grep '^pending=') == pending=1 ]] || fail 'ignored package counted as pending'
"$settings" --auto on >/dev/null
[[ -e $pending ]] || fail 'auto on with downloaded updates did not mark pending'
rm -f "$pending"
"$backend" check
[[ -e $pending ]] || fail 'check did not mark pending while on'
touch "$OMARCHY_JETSON_PACMAN_LOCK"
: >"$CALLS"
"$backend" check
! grep -q checkupdates "$CALLS" || fail 'check ran during a pacman transaction'
rm -f "$OMARCHY_JETSON_PACMAN_LOCK"
pass 'check lists, pre-downloads and hands over only when switched on'

# --- apply: each gate blocks --------------------------------------------------
applied() { grep -q '^omarchy-update-system-pkgs' "$CALLS"; }
expect_blocked() { # description, log-substring, [drops-marker]
  : >"$CALLS"
  touch "$pending"
  "$backend" apply
  ! applied || fail "$1: update ran"
  if [[ ${3:-} == drops-marker ]]; then
    [[ ! -e $pending ]] || fail "$1: pending kept, would retry every 15 minutes"
  else
    [[ -e $pending ]] || fail "$1: pending marker dropped"
  fi
  tail -n 1 "$OMARCHY_JETSON_UPDATE_LOG" | grep -Fq "$2" || fail "$1: log says $(tail -n 1 "$OMARCHY_JETSON_UPDATE_LOG")"
  pass "apply gate: $1"
}

"$settings" --auto off >/dev/null
: >"$CALLS"
touch "$pending"
"$backend" apply
! applied || fail 'switched off: update ran'
[[ ! -e $pending ]] || fail 'switched off: pending marker kept'
pass 'apply gate: switched off'
"$settings" --auto on >/dev/null

FAKE_CONNECTIVITY=limited expect_blocked 'not fully online' 'not fully online'
touch "$OMARCHY_JETSON_PACMAN_LOCK"
expect_blocked 'pacman database lock' 'pacman transaction'
rm -f "$OMARCHY_JETSON_PACMAN_LOCK"

mkdir -p "$fixture/run/1000"
lock=$fixture/run/1000/omarchy-update.lock
: >"$lock"
exec {lock_fd}>"$lock"
flock -n "$lock_fd"
expect_blocked 'interactive omarchy-update running' 'Omarchy update is running'
exec {lock_fd}>&-

FAKE_AVAIL_KIB=$((2 * 1024 * 1024 - 1)) expect_blocked 'less than 2 GiB free' 'GiB free'
printf '2 wayland user no no\n' >"$FAKE_SESSIONS"
expect_blocked 'active desktop session' 'session is in use'
printf '2 wayland user yes no\n3 x11 user no no\n' >"$FAKE_SESSIONS"
expect_blocked 'one of two sessions active' 'session is in use'
printf '1 unspecified manager no no\n2 wayland user no yes\n4 wayland greeter no no\n9 tty user no no\n' >"$FAKE_SESSIONS"
FAKE_CHECK_RC=1 expect_blocked 'fresh check fails' 'could not reach'

# --- apply: kernel/BSP and hold gates post a notice --------------------------
for kernel_pkg in linux-jetson linux-jetson-headers nvidia-jetson-userspace; do
  printf 'mesa 1.0-1 -> 1.1-1\n%s 1-1 -> 2-1\n' "$kernel_pkg" >"$FAKE_UPDATES"
  rm -f "$notice"
  expect_blocked "kernel/BSP pending ($kernel_pkg)" 'kernel/BSP update needs the user' drops-marker
  [[ $(head -n 1 "$notice") == kernel ]] || fail "$kernel_pkg: no kernel notice"
  grep -Fq "$kernel_pkg" "$notice" || fail "$kernel_pkg: notice does not name the package"
  grep -Fq 'No kernel backup will be taken' "$notice" || fail "$kernel_pkg: notice hides the missing backup"
done
# With omarchy-jetson-kernel-safety installed, the notice says a backup is taken.
touch "$fixture/kernel-backup.hook"
printf 'linux-jetson 1-1 -> 2-1\n' >"$FAKE_UPDATES"
OMARCHY_JETSON_KERNEL_BACKUP_HOOK=$fixture/kernel-backup.hook expect_blocked 'kernel/BSP pending, backup hook present' 'kernel/BSP update needs the user' drops-marker
grep -Fq 'saved to /boot/last-good first' "$notice" || fail "notice does not mention the backup: $(<"$notice")"
printf 'mesa 1.0-1 -> 1.1-1\nlinux-aarch64 6.1-1 -> 6.2-1\n' >"$FAKE_UPDATES"
expect_blocked 'generic kernel no longer ignored' 'kernel/BSP update needs the user' drops-marker
printf 'mesa 1.0-1 -> 1.1-1\n' >"$FAKE_UPDATES"
rm -f "$notice"
FAKE_IGNORED=linux-aarch64 expect_blocked 'IgnorePkg hold incomplete' 'IgnorePkg no longer holds' drops-marker
[[ $(head -n 1 "$notice") == kernel ]] || fail 'missing hold posted no notice'

# --- apply: success through upstream's update steps --------------------------
# The released lock file is still there and must not block.
[[ -f $lock ]] || fail 'lock fixture missing'
printf 'mesa 1.0-1 -> 1.1-1\nlibdrm 2.4-1 -> 2.5-1\nlinux-aarch64 6.1-1 -> 6.2-1 [ignored]\n' >"$FAKE_UPDATES"
: >"$CALLS"
touch "$pending"
"$backend" apply
expected_calls=$(printf '%s\n' 'omarchy-update-lock run' 'omarchy-update-pkg-prune' 'omarchy-snapshot create' \
  'omarchy-update-keyring' "omarchy-update-system-pkgs unattended=1 path=/usr/share/omarchy")
[[ $(grep -v '^checkupdates' "$CALLS") == "$expected_calls" ]] || fail "upstream steps: $(<"$CALLS")"
! grep -Eq '^(pacman|sudo|systemctl)' "$CALLS" || fail 'apply bypassed upstream or touched systemd'
! grep -Eq 'reboot|omarchy-update-restart' "$CALLS" || fail 'apply must never reboot'
[[ ! -e $pending ]] || fail 'pending kept after success'
[[ $(head -n 1 "$notice") == ok ]] || fail 'no ok notice'
grep -Fq '2 update(s)' "$notice" || fail "ok notice count: $(<"$notice")"
pass 'apply runs upstream omarchy-update system steps and posts an ok notice'

touch "$pending"
FAKE_SYSPKGS_RC=1 "$backend" apply
tail -n 1 "$OMARCHY_JETSON_UPDATE_LOG" | grep -Fq 'failed; will retry' || fail 'failure not logged'
[[ -e $pending ]] || fail 'failed update dropped the pending marker'
[[ $(head -n 1 "$notice") == failed ]] || fail 'no failed notice'
pass 'failed update keeps the marker and posts a failed notice'

# --- notify: each notice shown once ------------------------------------------
: >"$CALLS"
"$notify"
grep -Fq 'notify -u critical Automatic update did not finish' "$CALLS" || fail "failed notice not shown: $(<"$CALLS")"
: >"$CALLS"
"$notify"
[[ ! -s $CALLS ]] || fail 'notice shown twice'
printf 'ok\n3 update(s) were installed.\n' >"$notice"
"$notify"
grep -Fq 'notify -u normal Updates installed' "$CALLS" || fail 'ok notice not shown'
grep -Fxq 'omarchy-migrate-notify' "$CALLS" || fail 'ok notice did not hand over to omarchy-migrate-notify'
printf 'kernel\nlinux-jetson waits.\n' >"$notice"
"$notify"
grep -Fq 'notify -u critical Kernel update needs you' "$CALLS" || fail 'kernel notice not shown'
pass 'notifications turn each notice into one desktop notification'

printf 'PASS  automatic update fixture\n'
