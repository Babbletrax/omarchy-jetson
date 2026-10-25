#!/usr/bin/env bash
# Fixture test for omarchy-jetson-kernel-safety: the last-good kernel backup,
# the managed extlinux.conf entry, the early-boot module mount and the pacman
# hook. Everything runs against a fake root (OMARCHY_JETSON_ROOT) with fake
# uname, pacman, df, mount and systemd-detect-virt on PATH; nothing here reads
# or writes the host's /boot, /usr/lib/modules or mounts.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pkg=$repo_root/packages/omarchy-jetson-kernel-safety
tool=$pkg/omarchy-jetson-kernel
hook=$pkg/10-omarchy-jetson-kernel-backup.hook
unit=$pkg/omarchy-jetson-kernel-modules.service

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
  fake uname 'printf "%s\n" "${FAKE_UNAME:-6.8.12-1021-tegra}"'
  fake df 'printf "Avail\n%s\n" "${FAKE_AVAIL_KIB:-99999999}"'
  fake systemd-detect-virt 'exit "${FAKE_VIRT_RC:-1}"'
  fake pacman '
    case "$*" in
      "-Qq linux-jetson") [[ ${FAKE_INSTALLED:-yes} == yes ]] && echo linux-jetson || exit 1 ;;
      "-Qlq linux-jetson") [[ ${FAKE_INSTALLED:-yes} == yes ]] && printf "/boot/\n/boot/Image-%s\n" "${FAKE_PKG_KVER:-6.8.12-1021-tegra}" || exit 1 ;;
      "-Q linux-jetson") echo "linux-jetson 6.8.12.1021-2" ;;
      "-Q") printf "bash 5-1\nlinux-jetson 6.8.12.1021-2\nlinux-jetson-initrd 6.8.12.1021-1\nnvidia-jetson-userspace 39.2.1-6\n" ;;
      *) exit 1 ;;
    esac'
  fake mount '
    printf "mount %s\n" "$*" >>"$CALLS"
    printf "%s %s none ro,bind 0 0\n" "${@: -2:1}" "${@: -1}" >>"$OMARCHY_JETSON_ROOT/proc/mounts"'
  fake umount '
    printf "umount %s\n" "$*" >>"$CALLS"
    grep -vF " ${@: -1} " "$OMARCHY_JETSON_ROOT/proc/mounts" >"$OMARCHY_JETSON_ROOT/proc/mounts.new" || true
    mv "$OMARCHY_JETSON_ROOT/proc/mounts.new" "$OMARCHY_JETSON_ROOT/proc/mounts"'
}

export PATH="$bin:/usr/bin:/bin"
export CALLS=$fixture/calls
export OMARCHY_JETSON_ROOT=$fixture/root
R=$OMARCHY_JETSON_ROOT
V=6.8.12-1021-tegra
conf=$R/boot/extlinux/extlinux.conf
lg=$R/boot/last-good
# shellcheck disable=SC2016 # ${cbootargs} is literal extlinux.conf text
append_original='${cbootargs} root=PARTUUID=00000000-0000-4000-8000-000000000001 rw rootwait rootfstype=ext4 console=ttyTCU0,115200 console=tty0 firmware_class.path=/etc/firmware'

write_conf() { # extra lines for the DEFAULT entry
  cat >"$conf" <<EOF
TIMEOUT 50
DEFAULT original

MENU TITLE Test boot options

# NVIDIA's stock comment, kept verbatim:
# LABEL backup
#    LINUX /boot/Image.backup

LABEL diagnostic
      MENU LABEL diagnostic boot
      LINUX /boot/Image
      INITRD /boot/initrd
      APPEND ${append_original} loglevel=8

LABEL original
      MENU LABEL original flashed boot arguments
      LINUX /boot/Image
      INITRD /boot/initrd${1:+
$1}
      APPEND ${append_original}
EOF
}

# A booted system: kernel, initrd and modules installed before this boot.
make_tree() {
  [[ -e $R ]] && { chmod -R u+rwX "$R"; rm -r -- "$R"; }
  mkdir -p "$R/boot/extlinux" "$R/boot/dtb" "$R/proc" "$R/usr/lib/modules/$V/kernel/drivers" \
    "$R/usr/lib/modules/$V/updates/drivers/net"
  printf 'kernel-image-A\n' >"$R/boot/Image-$V"
  ln -s "Image-$V" "$R/boot/Image"
  printf 'initrd-A\n' >"$R/boot/initrd-$V"
  chmod 600 "$R/boot/initrd-$V"
  ln -s "initrd-$V" "$R/boot/initrd"
  printf 'dtb-A\n' >"$R/boot/dtb/board.dtb"
  printf 'ko-A\n' >"$R/usr/lib/modules/$V/kernel/drivers/foo.ko"
  printf 'nvgpu-A\n' >"$R/usr/lib/modules/$V/updates/nvgpu.ko"
  printf 'nvethernet-A\n' >"$R/usr/lib/modules/$V/updates/drivers/net/nvethernet.ko"
  printf 'foo.ko:\n' >"$R/usr/lib/modules/$V/modules.dep"
  ln -s "/usr/src/linux-headers-$V" "$R/usr/lib/modules/$V/build"
  write_conf
  printf '%s\n' "${append_original//\$\{cbootargs\} /}" >"$R/proc/cmdline"
  booted_after_install
  : >"$R/proc/mounts"
  : >"$CALLS"
}
booted_after_install() { printf 'cpu 1 2 3\nbtime %s\n' "$(($(date +%s) + 1000))" >"$R/proc/stat"; }
installed_after_boot() { printf 'cpu 1 2 3\nbtime %s\n' "$(($(date +%s) - 1000))" >"$R/proc/stat"; }

run() { "$tool" "$@" 2>"$fixture/err"; }
err() { cat "$fixture/err"; }
conf_backups() { find "$R/boot/extlinux" -name 'extlinux.conf.omarchy-jetson-*.bak' | wc -l; }
# The original file minus the managed block (and the blank line before it).
without_block() {
  awk '/^# >>> omarchy-jetson last-good/ { skip = 1; next } skip && /^# <<< omarchy-jetson last-good/ { skip = 0; next } !skip' "$1" |
    sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

# --- hook and unit contract --------------------------------------------------
targets=$(sed -n 's/^Target = //p' "$hook" | sort | paste -sd' ')
[[ $targets == 'linux-aarch64 linux-jetson linux-jetson-initrd nvidia-jetson-*' ]] || fail "hook targets: $targets"
! grep -q '^Target = linux-jetson-headers' "$hook" || fail 'headers must not trigger a backup'
grep -Fxq 'When = PreTransaction' "$hook" || fail 'hook is not PreTransaction'
grep -Fxq 'AbortOnFail' "$hook" || fail 'hook does not abort on failure'
grep -Fxq 'Exec = /usr/bin/omarchy-jetson-kernel backup' "$hook" || fail 'hook Exec'
[[ $(sed -n 's/^Operation = //p' "$hook" | sort | paste -sd' ') == 'Install Remove Upgrade' ]] || fail 'hook operations'
# shellcheck disable=SC2016 # literal PKGBUILD text
grep -Fq '"$pkgdir/usr/bin/omarchy-jetson-kernel"' "$pkg/PKGBUILD" || fail 'PKGBUILD does not install the tool where the hook runs it'
# shellcheck disable=SC2016 # literal PKGBUILD text
grep -Fq '"$pkgdir/usr/share/libalpm/hooks/10-omarchy-jetson-kernel-backup.hook"' "$pkg/PKGBUILD" || fail 'hook not installed'
grep -Fq 'sysinit.target.wants/omarchy-jetson-kernel-modules.service' "$pkg/PKGBUILD" || fail 'unit not statically wanted'
grep -Fxq 'DefaultDependencies=no' "$unit" || fail 'unit has default dependencies'
before=$(sed -n 's/^Before=//p' "$unit")
for u in systemd-udevd.service systemd-udev-trigger.service systemd-modules-load.service; do
  [[ " $before " == *" $u "* ]] || fail "unit is not ordered before $u"
done
marker=$(sed -n "s/^marker=//p" "$tool")
grep -Fxq "ConditionKernelCommandLine=$marker" "$unit" || fail "unit condition does not match the marker $marker"
grep -Fxq 'ExecStart=/usr/bin/omarchy-jetson-kernel restore-modules' "$unit" || fail 'unit ExecStart'
grep -Fxq 'omarchy-jetson-kernel-safety' "$repo_root/config/workstation-packages.txt" || fail 'not in the base package list'
pass 'hook targets the kernel, initrd, NVIDIA BSP and generic kernel; unit runs before udev'

# --- backup: first run -------------------------------------------------------
make_tree
original=$(<"$conf")
run backup || fail "first backup failed: $(err)"
[[ -d $lg && ! -e $R/boot/last-good.tmp ]] || fail 'no last-good set, or a leftover tmp'
[[ $(<"$lg/VERSION") == "$V" ]] || fail 'VERSION'
cmp -s "$lg/Image" "$R/boot/Image-$V" || fail 'Image differs'
cmp -s "$lg/initrd" "$R/boot/initrd-$V" || fail 'initrd differs'
[[ $(stat -c %a "$lg/initrd") == 600 ]] || fail 'initrd mode not kept'
[[ ! -e $lg/dtb ]] || fail 'copied a DTB the entry does not reference'
cmp -s "$lg/modules/$V/updates/nvgpu.ko" "$R/usr/lib/modules/$V/updates/nvgpu.ko" || fail 'NVIDIA OOT module not saved'
[[ -L $lg/modules/$V/build ]] || fail 'modules tree not copied as-is'
(cd "$lg" && sha256sum --quiet -c SHA256SUMS) || fail 'SHA256SUMS does not verify'
for f in Image initrd "modules/$V/updates/nvgpu.ko" "modules/$V/kernel/drivers/foo.ko" "modules/$V/modules.dep"; do
  grep -Eq "^[0-9a-f]{64}  $f\$" "$lg/SHA256SUMS" || fail "SHA256SUMS lacks $f"
done
grep -Fxq "version=$V" "$lg/MANIFEST" || fail 'MANIFEST version'
grep -Fxq "image=/boot/Image-$V" "$lg/MANIFEST" || fail 'MANIFEST image path is not root-relative'
grep -Fq 'fdt=none' "$lg/MANIFEST" || fail 'MANIFEST does not note the firmware DTB'
grep -Fxq 'package=nvidia-jetson-userspace 39.2.1-6' "$lg/MANIFEST" || fail 'MANIFEST packages'
! grep -q '^package=bash' "$lg/MANIFEST" || fail 'MANIFEST lists unrelated packages'
"$tool" verify >/dev/null 2>&1 || fail 'verify fails on a good set'
pass 'backup saves the running kernel, initrd and module tree with a manifest and SHA256SUMS'

grep -Fxq 'DEFAULT original' "$conf" || fail 'DEFAULT changed'
[[ $(without_block "$conf") == "$original" ]] || fail "lines outside the managed block changed: $(diff <(printf '%s\n' "$original") <(without_block "$conf"))"
block=$(sed -n '/^# >>> omarchy-jetson last-good/,/^# <<< omarchy-jetson last-good/p' "$conf")
expected_block="# >>> omarchy-jetson last-good (managed by omarchy-jetson-kernel; do not edit) >>>
LABEL last-good
      MENU LABEL last-good: previous working kernel $V
      LINUX /boot/last-good/Image
      INITRD /boot/last-good/initrd
      APPEND $append_original omarchy_jetson.last_good=1
# <<< omarchy-jetson last-good <<<"
[[ $block == "$expected_block" ]] || fail "managed block: $block"
[[ $(conf_backups) == 1 ]] || fail 'no timestamped extlinux.conf backup'
cmp -s <(printf '%s\n' "$original") "$(find "$R/boot/extlinux" -name 'extlinux.conf.omarchy-jetson-*.bak')" || fail 'backup is not the original'
pass 'extlinux.conf gains a managed last-good entry; DEFAULT and other entries are byte-identical'

# --- idempotence -------------------------------------------------------------
cp -p "$conf" "$fixture/conf.1"
inode=$(stat -c %i "$lg")
run backup || fail "second backup failed: $(err)"
cmp -s "$conf" "$fixture/conf.1" || fail 'second run changed extlinux.conf'
[[ $(conf_backups) == 1 ]] || fail 'second run made another extlinux.conf backup'
[[ $(stat -c %i "$lg") == "$inode" ]] || fail 'second run replaced an already current set'
grep -q 'already holds the running kernel' "$fixture/err" || fail "no 'already current' message: $(err)"
pass 'a second backup changes nothing'

# --- APPEND change re-syncs the block only ------------------------------------
sed -i "/LABEL original/,\$ s|APPEND .*|APPEND $append_original quiet|" "$conf"
cp "$conf" "$fixture/conf.2"
run backup || fail "backup after an APPEND change failed: $(err)"
grep -Fxq "      APPEND $append_original quiet omarchy_jetson.last_good=1" "$conf" || fail 'block APPEND not updated'
[[ $(grep -c '^LABEL last-good$' "$conf") == 1 ]] || fail 'more than one last-good entry'
[[ $(grep -c '^# >>> omarchy-jetson last-good' "$conf") == 1 ]] || fail 'more than one managed block'
[[ $(without_block "$conf") == "$(without_block "$fixture/conf.2")" ]] || fail 'update touched unmanaged lines'
[[ $(conf_backups) == 2 ]] || fail 'update kept no backup'
pass 'the block follows the DEFAULT entry APPEND line and stays unique'

# --- atomic replace with a new tested kernel ---------------------------------
printf 'kernel-image-B\n' >"$R/boot/Image-$V"
printf 'nvgpu-B\n' >"$R/usr/lib/modules/$V/updates/nvgpu.ko"
rm "$R/usr/lib/modules/$V/kernel/drivers/foo.ko"
booted_after_install
run backup || fail "replacing backup failed: $(err)"
grep -Fxq 'kernel-image-B' "$lg/Image" || fail 'last-good not replaced'
grep -Fxq 'nvgpu-B' "$lg/modules/$V/updates/nvgpu.ko" || fail 'modules not replaced'
[[ ! -e $lg/modules/$V/kernel/drivers/foo.ko ]] || fail 'old set mixed into the new one'
[[ ! -e $R/boot/last-good.tmp && ! -e $R/boot/last-good.old ]] || fail 'leftovers after the swap'
(cd "$lg" && sha256sum --quiet -c SHA256SUMS) || fail 'replaced set does not verify'
pass 'a newer running kernel replaces last-good in one swap'

# A copy that fails half-way leaves the old set alone and stops the update.
cp -a "$lg" "$fixture/lg.before"
printf 'nvgpu-C\n' >"$R/usr/lib/modules/$V/updates/nvgpu.ko"
chmod 000 "$R/usr/lib/modules/$V/updates/drivers/net/nvethernet.ko"
booted_after_install
if [[ $EUID != 0 ]]; then
  if run backup; then fail 'a failed copy succeeded'; fi
  grep -q 'left as it was' "$fixture/err" || fail "copy failure message: $(err)"
  diff -r "$fixture/lg.before" "$lg" >/dev/null || fail 'a failed copy changed last-good'
  [[ ! -e $R/boot/last-good.tmp ]] || fail 'a failed copy left last-good.tmp'
  pass 'a failed copy keeps the old last-good and aborts'
fi
chmod 644 "$R/usr/lib/modules/$V/updates/drivers/net/nvethernet.ko"

# Leftovers of an interrupted run are cleaned up.
mkdir -p "$R/boot/last-good.tmp/junk"
mv "$lg" "$R/boot/last-good.old"
run backup || fail "backup after an interrupted run failed: $(err)"
[[ -d $lg && ! -e $R/boot/last-good.tmp && ! -e $R/boot/last-good.old ]] || fail 'interrupted-run leftovers not resolved'
grep -Fxq 'nvgpu-C' "$lg/modules/$V/updates/nvgpu.ko" || fail 'backup after recovery is not current'
pass 'an interrupted swap is recovered on the next run'

# --- free space ---------------------------------------------------------------
make_tree
FAKE_AVAIL_KIB=1000 run backup && fail 'backup ran without enough space'
grep -q 'not enough free space' "$fixture/err" || fail "space message: $(err)"
[[ ! -e $lg && ! -e $R/boot/last-good.tmp ]] || fail 'space refusal still wrote files'
if [[ $(conf_backups) != 0 ]] || grep -q last-good "$conf"; then fail 'space refusal touched extlinux.conf'; fi
pass 'too little free space stops the update before anything is written'

# --- only the installed AND running kernel is saved -----------------------------
make_tree
FAKE_UNAME=6.8.12-9999-tegra run backup && fail 'unprotected update allowed for a foreign running kernel'
grep -q 'update is stopped' "$fixture/err" || fail "refusal message: $(err)"
[[ ! -e $lg ]] || fail 'saved a kernel that is not running'
pass 'no backup and no last-good: the update stops'

mkdir -p "$R/run/omarchy-jetson-kernel"
FAKE_UNAME=6.8.12-9999-tegra "$tool" allow-unprotected 2>/dev/null
FAKE_UNAME=6.8.12-9999-tegra run backup || fail "allow-unprotected was ignored: $(err)"
grep -q 'UNPROTECTED' "$fixture/err" || fail 'no unprotected warning'
[[ ! -e $R/run/omarchy-jetson-kernel/allow-unprotected && ! -e $lg ]] || fail 'allow-unprotected not consumed'
FAKE_UNAME=6.8.12-9999-tegra run backup && fail 'allow-unprotected applied twice'
pass 'allow-unprotected lets exactly one transaction through, with a warning'

run backup || fail "setup backup failed: $(err)"
cp -a "$lg" "$fixture/lg.A"
printf 'kernel-image-untested\n' >"$R/boot/Image-$V"
installed_after_boot
run backup || fail "pending-reboot run failed: $(err)"
grep -q 'reboot is pending' "$fixture/err" || fail "pending-reboot message: $(err)"
diff -r "$fixture/lg.A" "$lg" >/dev/null || fail 'promoted a kernel installed after this boot'
pass 'a kernel installed after this boot never becomes last-good'

FAKE_UNAME=6.8.12-9999-tegra run backup || fail "foreign kernel with a last-good failed: $(err)"
diff -r "$fixture/lg.A" "$lg" >/dev/null || fail 'foreign running kernel replaced last-good'
FAKE_PKG_KVER=6.8.12-0000-tegra run backup || fail 'unowned Image run failed'
grep -q 'is not installed by linux-jetson' "$fixture/err" || fail "unowned Image message: $(err)"
diff -r "$fixture/lg.A" "$lg" >/dev/null || fail 'an Image not owned by linux-jetson was saved'
pass 'a running kernel that is not the installed one keeps the existing last-good'

booted_after_install
printf '%s omarchy_jetson.last_good=1\n' "$(<"$R/proc/cmdline")" >"$R/proc/cmdline"
cp "$conf" "$fixture/conf.3"
run backup || fail "backup while on last-good failed: $(err)"
diff -r "$fixture/lg.A" "$lg" >/dev/null || fail 'running last-good replaced last-good'
cmp -s "$conf" "$fixture/conf.3" || fail 'running last-good edited extlinux.conf'
pass 'booted from last-good: nothing is promoted or edited'

printf '/dev/x %s none ro,bind 0 0\n' "$R/usr/lib/modules/$V" >"$R/proc/mounts"
run backup && fail 'backup ran over mounted last-good modules'
grep -q 'release-modules' "$fixture/err" || fail "mounted-modules message: $(err)"
: >"$R/proc/mounts"
pass 'mounted last-good modules stop a kernel update until released'

make_tree
FAKE_INSTALLED=no run backup || fail 'not-installed run failed'
FAKE_VIRT_RC=0 run backup || fail 'chroot run failed'
if [[ -e $lg ]] || grep -q last-good "$conf"; then fail 'no-kernel or chroot run wrote something'; fi
pass 'image builds (chroot/container) and systems without linux-jetson are left alone'

# --- FDT in the DEFAULT entry ------------------------------------------------
make_tree
write_conf '      FDT /boot/dtb/board.dtb'
run backup || fail "FDT backup failed: $(err)"
cmp -s "$lg/dtb" "$R/boot/dtb/board.dtb" || fail 'referenced DTB not saved'
grep -Eq '^[0-9a-f]{64}  dtb$' "$lg/SHA256SUMS" || fail 'DTB not in SHA256SUMS'
grep -Fxq '      FDT /boot/last-good/dtb' "$conf" || fail 'block lacks FDT'
grep -Fxq 'fdt=/boot/dtb/board.dtb' "$lg/MANIFEST" || fail 'MANIFEST fdt'
pass 'a DEFAULT entry FDT is saved and referenced'

# --- unparsable extlinux.conf is refused untouched ----------------------------
bad_case() { # description, sed-or-script
  make_tree
  eval "$2"
  rm -f "$fixture/conf.bad"
  [[ ! -e $conf ]] || cp -p "$conf" "$fixture/conf.bad"
  if run backup; then fail "accepted extlinux.conf with $1"; fi
  if [[ -e $fixture/conf.bad ]]; then
    cmp -s "$conf" "$fixture/conf.bad" || fail "$1: extlinux.conf changed"
  else
    [[ ! -e $conf ]] || fail "$1: created extlinux.conf"
  fi
  [[ $(conf_backups) == 0 && ! -e $lg ]] || fail "$1: wrote files"
  grep -q 'could not be parsed' "$fixture/err" || fail "$1: message: $(err)"
}
bad_case 'no DEFAULT' "sed -i '/^DEFAULT/d' \"\$conf\""
bad_case 'two DEFAULT lines' "sed -i '1a DEFAULT diagnostic' \"\$conf\""
bad_case 'DEFAULT to a missing label' "sed -i 's/^DEFAULT original/DEFAULT nothere/' \"\$conf\""
bad_case 'DEFAULT last-good' "sed -i 's/^DEFAULT original/DEFAULT last-good/' \"\$conf\""
bad_case 'a duplicate LABEL' "printf 'LABEL diagnostic\n  LINUX /boot/Image\n' >>\"\$conf\""
bad_case 'an unknown directive' "sed -i 's/^TIMEOUT 50/TIMEOUT 50\nBOGUS thing/' \"\$conf\""
bad_case 'an unclosed managed block' "printf '# >>> omarchy-jetson last-good (managed by omarchy-jetson-kernel; do not edit) >>>\nLABEL last-good\n' >>\"\$conf\""
bad_case 'a stray block end' "printf '# <<< omarchy-jetson last-good <<<\n' >>\"\$conf\""
bad_case 'last-good outside the block' "printf 'LABEL last-good\n  LINUX /boot/Image\n' >>\"\$conf\""
bad_case 'a DEFAULT entry without APPEND' "sed -i '\$d' \"\$conf\""
bad_case 'a relative LINUX path' "sed -i '/LABEL original/,\$ s|LINUX /boot/Image|LINUX Image|' \"\$conf\""
bad_case 'FDTDIR in the DEFAULT entry' "sed -i '\$a\\      FDTDIR /boot/dtb' \"\$conf\""
bad_case 'DOS line endings' "sed -i 's/\$/\r/' \"\$conf\""
bad_case 'a missing file' "rm \"\$conf\""
pass 'an extlinux.conf the tool cannot parse is refused and left byte-identical'

# --- modules restore ---------------------------------------------------------
make_tree
run backup || fail "setup failed: $(err)"
: >"$CALLS"
run restore-modules || fail 'restore-modules on a normal boot failed'
[[ ! -s $CALLS ]] || fail "normal boot mounted something: $(<"$CALLS")"

printf '%s omarchy_jetson.last_good=1\n' "$(<"$R/proc/cmdline")" >"$R/proc/cmdline"
run restore-modules || fail "restore with modules present failed: $(err)"
grep -Fxq "mount --bind -o ro -- $lg/modules/$V $R/usr/lib/modules/$V" "$CALLS" || fail "mount call: $(<"$CALLS")"
: >"$CALLS"
run restore-modules || fail 'second restore failed'
[[ ! -s $CALLS ]] || fail 'mounted twice'
pass 'last-good boot mounts its saved modules read-only over a present tree, once'

run release-modules || fail "release failed: $(err)"
grep -Fxq "umount -- $R/usr/lib/modules/$V" "$CALLS" || fail "umount call: $(<"$CALLS")"
[[ -d $R/usr/lib/modules/$V ]] || fail 'release removed a package-owned module tree'

# pacman removed the old kernel's modules: the mountpoint is created.
chmod -R u+rwX "$R/usr/lib/modules/$V"
rm -r -- "$R/usr/lib/modules/$V"
: >"$CALLS"
run restore-modules || fail "restore with modules missing failed: $(err)"
[[ -d $R/usr/lib/modules/$V ]] || fail 'no mountpoint created'
grep -Fxq "mount --bind -o ro -- $lg/modules/$V $R/usr/lib/modules/$V" "$CALLS" || fail "mount call: $(<"$CALLS")"
"$tool" status | grep -Fq 'saved modules mounted' || fail 'status does not report the mount'
run release-modules || fail 'release failed'
[[ ! -e $R/usr/lib/modules/$V ]] || fail 'release left the created mountpoint'

printf 'other-version\n' >"$lg/VERSION"
: >"$CALLS"
run restore-modules || fail 'version mismatch run failed'
[[ ! -s $CALLS ]] || fail 'mounted modules of another version'
pass 'missing module trees get a mountpoint; another version is never mounted'

# --- status and verify -------------------------------------------------------
make_tree
s=$("$tool" status 2>/dev/null)
grep -Fxq "running:        $V" <<<"$s" || fail "status running: $s"
grep -Fxq 'last-good:      none' <<<"$s" || fail "status none: $s"
grep -Fq 'backup current: no' <<<"$s" || fail "status current: $s"
grep -Fq 'boot entry:     missing (DEFAULT is original)' <<<"$s" || fail "status entry: $s"
run backup
s=$("$tool" status 2>/dev/null)
grep -Fq "last-good:      $V (saved " <<<"$s" || fail "status last-good: $s"
grep -Fxq 'backup current: yes' <<<"$s" || fail "status current after backup: $s"
grep -Fq 'boot entry:     present' <<<"$s" || fail "status entry present: $s"
printf 'kernel-image-new\n' >"$R/boot/Image-$V"
grep -Fq 'backup current: no (the installed kernel differs' <<<"$("$tool" status 2>/dev/null)" || fail 'status misses a changed kernel'
printf 'tampered\n' >"$lg/Image"
"$tool" verify >/dev/null 2>&1 && fail 'verify accepted a tampered set'
pass 'status reports running, saved and current; verify catches tampering'
