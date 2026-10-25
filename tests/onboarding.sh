#!/usr/bin/env bash
# Fixture test for omarchy-jetson-onboarding: when first-boot setup runs, the
# username and hostname rules, an existing hostname kept, resume after an
# interruption, the setup-done gate and the unit's place before greetd.
# Every system command is a fake on PATH and every file lives in a fixture
# root (--root); nothing here touches the host.
# Single-quoted '$...' below is literal text to match, not an expansion.
# shellcheck disable=SC2016
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pkg=$repo_root/packages/omarchy-jetson-onboarding
onboard=$pkg/omarchy-jetson-onboard
unit=$pkg/omarchy-jetson-onboarding.service

fixture=$(mktemp -d)
trap 'rm -r -- "$fixture"' EXIT
bin=$fixture/bin
mkdir -p "$bin"

fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS  %s\n' "$*"; }

fake() { # name, body; FAKE_CRASH_ON=name kills the whole run there (power loss)
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %q "$*" >>"$CALLS"\n[[ ${FAKE_CRASH_ON:-} == %q ]] && kill -KILL 0\n%s\n' \
    "$1" "$1" "$2" >"$bin/$1"
  chmod +x "$bin/$1"
}

# The fake bodies are literal script source.
{
  # gum: styled text is dropped; every prompt takes the next line of
  # $ANSWERS. <esc> and <ctrl-c> exit as gum does; running out of answers
  # ends the run, so a prompt that should not appear fails the test.
  fake gum '
    sub=$1
    case $sub in
      style) exit 0 ;;
      choose | filter) cat >"$FIXTURE/last-list" ;;
    esac
    pos=$(cat "$ANSWERS.pos" 2>/dev/null || echo 0)
    pos=$((pos + 1))
    echo "$pos" >"$ANSWERS.pos"
    if ((pos > $(wc -l <"$ANSWERS"))); then
      echo "OUT OF ANSWERS at: $*" >>"$CALLS"
      kill -KILL 0
    fi
    line=$(sed -n "${pos}p" "$ANSWERS")
    case $line in
      "<esc>") exit 1 ;;
      "<ctrl-c>") exit 130 ;;
    esac
    if [[ $sub == confirm ]]; then [[ $line == yes ]]; exit; fi
    printf "%s\n" "$line"'
  fake nmcli '
    case "$*" in
      "-t -f CONNECTIVITY general") echo "${FAKE_CONNECTIVITY:-full}" ;;
      "-t -f TYPE,STATE device") printf "%s\n" ${FAKE_DEVICES:-ethernet:connected} ;;
      "-t -f TYPE device") printf "%s\n" ${FAKE_DEVICES:-ethernet:connected} | cut -d: -f1 ;;
      *"wifi list"*) printf "%s\n" FixtureNet FixtureNet CafeNet ;;
      *"wifi connect"*) exit "${FAKE_WIFI_RC:-0}" ;;
    esac'
  fake useradd '
    root=/ groups="" name=""
    while (($#)); do
      case $1 in
        --root) root=$2; shift 2 ;;
        -G) groups=$2; shift 2 ;;
        -s | -c) shift 2 ;;
        -m) shift ;;
        *) name=$1; shift ;;
      esac
    done
    echo "$name:x:1001:1001::/home/$name:/bin/bash" >>"$root/etc/passwd"
    echo "$name:!:20000::::::" >>"$root/etc/shadow"
    echo "$name:x:1001:" >>"$root/etc/group"
    echo "$groups" >"$FIXTURE/groups-$name"'
  fake usermod ':'
  fake chpasswd '
    root=/; [[ ${1:-} == --root ]] && root=$2
    IFS=: read -r user pass
    awk -F: -v OFS=: -v u="$user" "\$1 == u {\$2 = \"HASHED\"} {print}" "$root/etc/shadow" >"$root/etc/shadow.new"
    mv "$root/etc/shadow.new" "$root/etc/shadow"
    printf "%s\n" "$pass" >"$FIXTURE/password-$user"'
  fake visudo 'exit 0'
  fake runuser '
    while (($#)) && [[ $1 != -- ]]; do shift; done
    shift
    exec "$@"'
  fake omarchy-provision-user '
    printf "provision context=%s user=%s home=%s args=%s\n" "$OMARCHY_SETUP_CONTEXT" "$USER" "$HOME" "$*" >>"$CALLS"
    exit "${FAKE_PROVISION_RC:-0}"'
  fake pacman-key '
    [[ $1 == --gpgdir ]] && mkdir -p "$2" && [[ $3 == --init ]] && echo fresh >"$2/machine-key"
    exit 0'
  fake gpgconf ':'
  fake systemd-firstboot ':'
  fake loadkeys ':'
  fake hostnamectl ':'
  fake systemctl ':'
  fake chown ':'
  fake timedatectl '[[ $1 == list-timezones ]] && printf "%s\n" America/New_York Europe/Berlin UTC'
  fake tzupdate 'echo "${FAKE_TZ_GUESS:-Europe/Berlin}"'
}

export PATH="$bin:/usr/bin:/bin"
export CALLS=$fixture/calls FIXTURE=$fixture ANSWERS=$fixture/answers
export OMARCHY_JETSON_ONBOARD_NET_WAIT=0 OMARCHY_JETSON_ONBOARD_DELAY=0
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
unset FAKE_CRASH_ON FAKE_CONNECTIVITY FAKE_DEVICES

# A fresh image: Arch Linux ARM's 'alarm' account locked, the seeded default
# hostname, UTC and a keyring that came with the image.
make_root() {
  local r=$1
  [[ ! -e $r ]] || rm -r -- "$r"
  mkdir -p "$r/etc/sudoers.d" "$r/etc/pacman.d/gnupg" "$r/var/cache" \
    "$r/usr/share/zoneinfo/Europe" "$r/usr/share/zoneinfo/America"
  printf '%s\n' 'root:x:0:0::/root:/bin/bash' 'alarm:x:1000:1000::/home/alarm:/bin/bash' \
    'greeter:x:965:965::/:/bin/bash' 'nobody:x:65534:65534::/:/usr/bin/nologin' >"$r/etc/passwd"
  printf '%s\n' 'root:!*:20000::::::' 'alarm:!$6$locked:20000:0:99999:7:::' 'greeter:!*:20000::::::' \
    'nobody:!*:20000::::::' >"$r/etc/shadow"
  printf '%s\n' 'root:x:0:' 'wheel:x:998:alarm' 'video:x:983:' 'render:x:987:' 'audio:x:995:' \
    'input:x:992:' 'alarm:x:1000:' 'greeter:x:965:' >"$r/etc/group"
  printf '%s\n' 'UID_MIN 1000' 'UID_MAX 60000' >"$r/etc/login.defs"
  echo omarchy-jetson >"$r/etc/hostname"
  touch "$r/usr/share/zoneinfo/UTC" "$r/usr/share/zoneinfo/Europe/Berlin" "$r/usr/share/zoneinfo/America/New_York"
  ln -s ../usr/share/zoneinfo/UTC "$r/etc/localtime"
  echo image >"$r/etc/pacman.d/gnupg/machine-key"
}

answers() { printf '%s\n' "$@" >"$ANSWERS"; rm -f "$ANSWERS.pos"; : >"$CALLS"; }

run() { # root [args...]: one onboarding run in its own process group
  local r=$1
  shift
  # A subshell, so the "Killed" job notice of a simulated power loss stays quiet.
  (setsid -w timeout 60 "$onboard" --root "$r" "$@" </dev/null >"$fixture/out" 2>&1; exit $?) 2>/dev/null
}

root=$fixture/root
homes=/home # where the fake useradd puts homes
state=$root/var/lib/omarchy-jetson/onboarding

# --- username and hostname rules --------------------------------------------
make_root "$root"
for good in alex a _svc dev-1 b_2 "$(printf 'a%.0s' {1..32})"; do
  "$onboard" --root "$root" --valid-username "$good" 2>/dev/null || fail "rejected username '$good'"
done
for bad in '' Alex 1abc 'a b' -x 'a$' 'x;rm' root alarm greeter nobody wheel video \
  "$(printf 'a%.0s' {1..33})"; do
  if "$onboard" --root "$root" --valid-username "$bad" 2>/dev/null; then fail "accepted username '$bad'"; fi
done
for good in omarchy-jetson Den-Box a x1 "$(printf 'h%.0s' {1..63})"; do
  "$onboard" --valid-hostname "$good" || fail "rejected hostname '$good'"
done
for bad in '' -x x- a_b a.b 'a b' "$(printf 'h%.0s' {1..64})"; do
  if "$onboard" --valid-hostname "$bad"; then fail "accepted hostname '$bad'"; fi
done
if [[ -r $OMARCHY_PATH/install/provisioning/setup-form.sh ]]; then
  if "$onboard" --root "$root" --valid-username sddm 2>/dev/null; then fail 'upstream reserved names are not applied'; fi
fi
pass 'username and hostname validation'

# --- runs only when needed ---------------------------------------------------
make_root "$root"
"$onboard" --root "$root" --check || fail 'a fresh image (locked alarm only) must need setup'
echo "kim:x:1001:1001::$homes/kim:/bin/bash" >>"$root/etc/passwd"
echo 'kim::20000::::::' >>"$root/etc/shadow"
if "$onboard" --root "$root" --check; then fail 'a key-only account must count as existing'; fi
answers
run "$root" --boot || fail "boot on a machine with an account failed: $(<"$fixture/out")"
[[ -s $state/done ]] || fail 'boot did not record the setup-done marker'
grep -q '^existing account' "$state/done" || fail "unexpected marker: $(<"$state/done")"
! grep -q '^gum ' "$CALLS" || fail "boot prompted on a machine that has an account: $(<"$CALLS")"
[[ $(<"$root/etc/hostname") == omarchy-jetson ]] || fail 'stand-down touched the hostname'

make_root "$root"
echo "sam:x:1001:1001::$homes/sam:/usr/bin/nologin" >>"$root/etc/passwd"
"$onboard" --root "$root" --check || fail 'a nologin account must not count'
mkdir -p "$state" && echo completed >"$state/done"
if "$onboard" --root "$root" --check; then fail 'the setup-done marker must stop setup'; fi
answers
run "$root" --boot || fail 'boot with the marker failed'
[[ ! -s $CALLS ]] || fail "boot with the marker ran something: $(<"$CALLS")"
pass 'setup runs only without a usable account and without the setup-done marker'

# --- full first boot -----------------------------------------------------------
make_root "$root"
answers 'English (US)' Alex alex pw1 pw2 's3cret pass' 's3cret pass' '' '' no '' yes Europe/Berlin
run "$root" --boot || fail "first boot failed: $(<"$fixture/out")"$'\n'"$(<"$CALLS")"
grep -q '^alex:x:1001:' "$root/etc/passwd" || fail 'account not created'
[[ $(<"$fixture/groups-alex") == wheel,video,render,audio ]] || fail "groups: $(<"$fixture/groups-alex")"
[[ $(<"$fixture/password-alex") == 's3cret pass' ]] || fail 'password not set from the confirmed entry'
grep -q '^alex:HASHED:' "$root/etc/shadow" || fail 'password not applied'
[[ $(grep -c '^useradd ' "$CALLS") == 1 ]] || fail 'useradd must run once'
[[ $(<"$root/etc/sudoers.d/00-omarchy-wheel") == '%wheel ALL=(ALL:ALL) ALL' ]] || fail 'wheel sudo grant missing'
[[ ! -e $root/etc/sudoers.d/90-passwordless-sudo-alex ]] || fail 'passwordless sudo must default to off'
[[ $(<"$root/etc/hostname") == omarchy-jetson ]] || fail "default hostname not kept: $(<"$root/etc/hostname")"
[[ $(readlink "$root/etc/localtime") == ../usr/share/zoneinfo/Europe/Berlin ]] || fail 'timezone not applied'
grep -q '^tzupdate -p' "$CALLS" || fail 'timezone detection not offered online'
[[ $(<"$root/etc/pacman.d/gnupg/machine-key") == fresh ]] || fail 'the image keyring was not replaced'
[[ ! -e $root/etc/pacman.d/gnupg.onboarding ]] || fail 'keyring staging directory left behind'
grep -Fq "provision context=provision-owner user=alex home=$homes/alex args=--force --first-install" "$CALLS" ||
  fail "upstream provisioning not handed the new account: $(grep provision "$CALLS" || true)"
! grep -q 'wifi connect' "$CALLS" || fail 'Wi-Fi offered while online'
[[ $(<"$root/var/cache/tuigreet/lastuser") == alex ]] || fail 'greeter not pointed at the new account'
[[ -s $state/done && ! -e $state/started && ! -e $state/user && ! -e $state/identity ]] ||
  fail "state not finished cleanly: $(ls "$state")"
for step in keyboard account hostname network timezone keyring provision; do
  [[ -e $state/steps/$step ]] || fail "step $step not recorded"
done
! grep -rqF 's3cret' "$root/var" "$CALLS" || fail 'the password leaked into a log or state file'
grep -q '^gum input --password' "$CALLS" || fail 'password prompts must be masked'
if "$onboard" --root "$root" --check; then fail 'setup still needed after completion'; fi
pass 'first boot creates the account, keeps the default hostname and hands over to upstream'

# --- hostname: kept when set, offered when a placeholder ------------------------
make_root "$root"
echo workbench >"$root/etc/hostname"
answers '<esc>' bea pw pw '' '' yes yes America/New_York
run "$root" --boot || fail "custom-hostname boot failed: $(<"$fixture/out")"
[[ $(<"$root/etc/hostname") == workbench ]] || fail 'an existing hostname was overwritten'
! grep -q 'Hostname>' "$CALLS" || fail 'asked for a hostname although one is set'
[[ $(<"$root/etc/sudoers.d/90-passwordless-sudo-bea") == 'bea ALL=(ALL:ALL) NOPASSWD: ALL' ]] ||
  fail 'passwordless sudo not written when chosen'
pass 'an existing hostname is kept; passwordless sudo only when chosen'

make_root "$root"
answers '<esc>' cai pw pw '' '' no 'bad_name' 'den-box' no '<esc>'
run "$root" --boot || fail "rename boot failed: $(<"$fixture/out")"
[[ $(<"$root/etc/hostname") == den-box ]] || fail "placeholder hostname not replaced: $(<"$root/etc/hostname")"
[[ $(readlink "$root/etc/localtime") == ../usr/share/zoneinfo/UTC ]] || fail 'skipping the timezone changed it'
make_root "$root"
rm "$root/etc/hostname"
answers '<esc>' dee pw pw '' '' no '' no '<esc>'
run "$root" --boot || fail "no-hostname boot failed: $(<"$fixture/out")"
[[ $(<"$root/etc/hostname") == omarchy-jetson ]] || fail 'missing hostname not defaulted'
pass 'the default hostname is offered and can be changed'

# --- offline: Wi-Fi via nmcli, timezone skippable --------------------------------
make_root "$root"
export FAKE_CONNECTIVITY=none FAKE_DEVICES='ethernet:unavailable wifi:disconnected'
answers '<esc>' eli pw pw '' '' no '' CafeNet wifipass '<esc>'
run "$root" --boot || fail "offline boot failed: $(<"$fixture/out")"
grep -Fq 'nmcli device wifi connect CafeNet password wifipass' "$CALLS" || fail 'Wi-Fi connect not attempted'
! grep -q '^tzupdate' "$CALLS" || fail 'timezone detection must not run offline'
grep -q '^gum filter' "$CALLS" || fail 'manual timezone choice not offered offline'
[[ -s $state/done ]] || fail 'offline setup did not finish'

make_root "$root"
answers '<esc>' fay pw pw '' '' no '' 'Skip, stay offline' '<esc>'
run "$root" --boot || fail "skip-network boot failed: $(<"$fixture/out")"
! grep -q 'wifi connect' "$CALLS" || fail 'skipping Wi-Fi still connected'
[[ -s $state/done ]] || fail 'setup without a network did not finish'
export FAKE_DEVICES=ethernet:connected
make_root "$root"
answers '<esc>' gus pw pw '' '' no '' '<esc>'
run "$root" --boot || fail "wired boot failed: $(<"$fixture/out")"
! grep -q 'wifi list' "$CALLS" || fail 'Wi-Fi offered with a wired link'
unset FAKE_CONNECTIVITY FAKE_DEVICES
pass 'offline setup offers Wi-Fi, skips it on a wired link, and timezone stays skippable'

# --- resume after an interruption -------------------------------------------------
make_root "$root"
answers '<esc>' hal pw pw '' '' no '' no '<esc>'
FAKE_CRASH_ON=pacman-key run "$root" --boot && fail 'the simulated power loss did not stop the run'
[[ ! -e $state/done && -e $state/started ]] || fail 'interrupted run left the wrong markers'
[[ -e $state/steps/account && ! -e $state/steps/keyring ]] || fail 'step markers wrong after interruption'
"$onboard" --root "$root" --check || fail 'an interrupted setup must resume although the account exists'
answers
run "$root" --boot || fail "resume failed: $(<"$fixture/out")"$'\n'"$(<"$CALLS")"
! grep -q '^gum \(input\|choose\|filter\|confirm\)' "$CALLS" || fail 'resume asked finished steps again'
! grep -q '^useradd' "$CALLS" || fail 'resume created the account again'
[[ -s $state/done && $(<"$root/etc/pacman.d/gnupg/machine-key") == fresh ]] || fail 'resume did not finish'

make_root "$root"
answers '<esc>' ivy pw pw '' '' no
FAKE_CRASH_ON=chpasswd run "$root" --boot && fail 'the interruption in the account step did not stop the run'
grep -q '^ivy:' "$root/etc/passwd" || fail 'fixture: account should exist before the interruption'
[[ ! -e $state/steps/account ]] || fail 'account step marked although the password was never set'
answers newpw newpw '' '' no '' no '<esc>'
run "$root" --boot || fail "account resume failed: $(<"$fixture/out")"
! grep -q 'Username>' "$CALLS" || fail 'resume asked for the username again'
grep -q '^usermod ' "$CALLS" || fail 'resume must reuse the existing account'
! grep -q '^useradd' "$CALLS" || fail 'resume created the account again'
[[ $(<"$fixture/password-ivy") == newpw ]] || fail 'resume did not set the password'
[[ $(grep -c '^ivy:' "$root/etc/passwd") == 1 ]] || fail 'resume made a second account'
pass 'an interrupted setup resumes at the first unfinished step'

# --- a failed upstream provisioning does not strand the machine ---------------------
make_root "$root"
answers '<esc>' jo pw pw '' '' no '' no '<esc>'
FAKE_PROVISION_RC=1 run "$root" --boot || fail 'a provisioning failure failed the whole setup'
[[ -s $state/done && -e $state/provision-warning ]] || fail 'provisioning failure not recorded as a warning'
pass 'a failed omarchy-provision-user leaves a working account and a retry hint'

# --- the unit: first boot, before greetd, on tty1 ------------------------------------
for line in 'ConditionPathExists=!/var/lib/omarchy-jetson/onboarding/done' \
  'Before=greetd.service display-manager.service getty@tty1.service' 'Conflicts=getty@tty1.service' \
  'Type=oneshot' 'TTYPath=/dev/tty1' 'StandardInput=tty' 'ExecStart=/usr/bin/omarchy-jetson-onboard --boot' \
  'WantedBy=multi-user.target'; do
  grep -Fxq "$line" "$unit" || fail "unit lacks: $line"
done
! grep -Eq '^(Requires|Wants|BindsTo)=.*greetd' "$unit" || fail 'the unit must only order itself before greetd'
grep -Fq 'install -Dm755 omarchy-jetson-onboard "$pkgdir/usr/bin/omarchy-jetson-onboard"' "$pkg/PKGBUILD" ||
  fail 'PKGBUILD does not install the command the unit runs'
grep -Fq 'usr/lib/systemd/system/omarchy-jetson-onboarding.service' "$pkg/PKGBUILD" || fail 'unit not packaged'
grep -Fq 'systemctl enable omarchy-jetson-onboarding.service' "$pkg/omarchy-jetson-onboarding.install" ||
  fail 'unit not enabled on install'
grep -Fq 'STATE=$R/var/lib/omarchy-jetson/onboarding' "$onboard" || fail 'script and unit disagree on the state path'
if command -v systemd-analyze >/dev/null; then
  mkdir -p "$fixture/units"
  sed "s|^ExecStart=/usr/bin/omarchy-jetson-onboard|ExecStart=$onboard|" "$unit" \
    >"$fixture/units/omarchy-jetson-onboarding.service"
  systemd-analyze verify "$fixture/units/omarchy-jetson-onboarding.service" >"$fixture/verify" 2>&1 ||
    fail "systemd-analyze verify: $(<"$fixture/verify")"
  pass 'the unit runs on tty1 before greetd and passes systemd-analyze verify'
else
  pass 'the unit runs on tty1 before greetd (systemd-analyze unavailable)'
fi
