#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
rootfs_archive="$repo_root/build/jetson-rootfs.tar"
efi_binary="$repo_root/build/nvidia-bsp/Linux_for_Tegra/bootloader/BOOTAA64.efi"
kernel_release=6.8.12-1021-tegra
expected_rootfs_sha256=9ce44225331bc2ab9737d57fc06bd375492e8c281d3a52084fd0b6c7af8402fe
minimum_size=$((8 * 1024 * 1024 * 1024))
maximum_size=$((128 * 1024 * 1024 * 1024))

device=
confirmed_serial=
ssh_public_key=
login_user=omarchy
write=0
root_mount=
esp_mount=

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: write-usb-test-drive.sh --device DEVICE --confirm-serial SERIAL \
       --ssh-public-key FILE [--user NAME] [--write]

--user renames the published 'alarm' account (default: omarchy).

Without --write, performs preflight checks only. --write irreversibly erases
the confirmed USB device.
EOF
}

cleanup() {
  set +e
  if [[ -n "$esp_mount" ]] && mountpoint -q "$esp_mount"; then
    umount "$esp_mount"
  fi
  [[ -z "$esp_mount" || ! -d "$esp_mount" ]] || rmdir "$esp_mount"
  if [[ -n "$root_mount" ]] && mountpoint -q "$root_mount"; then
    umount "$root_mount"
  fi
  [[ -z "$root_mount" || ! -d "$root_mount" ]] || rmdir "$root_mount"
}
trap cleanup EXIT

while (($#)); do
  case $1 in
    --device) device=${2:-}; shift 2 ;;
    --confirm-serial) confirmed_serial=${2:-}; shift 2 ;;
    --ssh-public-key) ssh_public_key=${2:-}; shift 2 ;;
    --user) login_user=${2:-}; shift 2 ;;
    --write) write=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; fail "unknown argument: $1" ;;
  esac
done

[[ -n "$device" && -n "$confirmed_serial" && -n "$ssh_public_key" ]] || {
  usage >&2
  exit 2
}
[[ $login_user =~ ^[a-z_][a-z0-9_-]{0,31}$ && $login_user != alarm && $login_user != root ]] ||
  fail "invalid --user name: $login_user"

for command_name in awk blkid bsdtar chown e2fsck findmnt fsck.fat grep install \
  lsblk mkfs.ext4 mkfs.fat mktemp mount mountpoint mv partprobe parted \
  sha256sum ssh-keygen stat sync udevadm umount unlink; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing host command: $command_name"
done

[[ -b "$device" ]] || fail "not a block device: $device"
[[ $(lsblk -dnro TYPE "$device") == disk ]] || fail "target is not a whole disk"
[[ $(lsblk -dnro TRAN "$device") == usb ]] || fail "target transport is not USB"
[[ $(lsblk -dnro RM "$device") == 1 ]] || fail "target is not removable"
[[ $(lsblk -dnro RO "$device") == 0 ]] || fail "target is read-only"

actual_serial=$(lsblk -dnro SERIAL "$device" | awk '{$1=$1; print}')
[[ -n "$actual_serial" ]] || fail 'target serial is unavailable'
[[ "$actual_serial" == "$confirmed_serial" ]] || fail 'target serial does not match confirmation'

device_size=$(lsblk -bdnro SIZE "$device")
((device_size >= minimum_size && device_size <= maximum_size)) || \
  fail "target size is outside the guarded 8-128 GiB range: $device_size"

[[ -f "$rootfs_archive" ]] || fail "missing rootfs archive: $rootfs_archive"
[[ -f "$efi_binary" ]] || fail "missing EFI binary: $efi_binary"
[[ -f "$ssh_public_key" ]] || fail "missing SSH public key: $ssh_public_key"
actual_rootfs_sha256=$(sha256sum "$rootfs_archive" | awk '{print $1}')
[[ "$actual_rootfs_sha256" == "$expected_rootfs_sha256" ]] || \
  fail 'rootfs archive SHA-256 does not match the reviewed artifact'
ssh-keygen -l -f "$ssh_public_key" >/dev/null || fail 'SSH public key is invalid'

if lsblk -nrpo MOUNTPOINTS "$device" | awk 'NF {found=1} END {exit !found}'; then
  fail 'target or one of its partitions is mounted; unmount it before writing'
fi

pass "confirmed removable USB target $device serial $actual_serial size $device_size"
pass 'rootfs archive, EFI binary, and SSH public key passed preflight'

if ((write == 0)); then
  printf 'Preflight only; no storage was changed. Add --write to erase the confirmed device.\n'
  exit 0
fi

((EUID == 0)) || fail '--write must run as root'

case $device in
  *[0-9]) esp_partition=${device}p1; root_partition=${device}p2 ;;
  *) esp_partition=${device}1; root_partition=${device}2 ;;
esac

parted --script "$device" -- mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB set 1 esp on \
  mkpart root ext4 513MiB 100%
partprobe "$device"
udevadm settle
[[ -b "$esp_partition" && -b "$root_partition" ]] || fail 'expected partitions did not appear'

mkfs.fat -F 32 -n JETSON_EFI "$esp_partition"
mkfs.ext4 -F -L JETSON_ARCH "$root_partition"

root_mount=$(mktemp -d /tmp/omarchy-jetson-root.XXXXXX)
esp_mount="$root_mount/boot/efi"
mount "$root_partition" "$root_mount"
bsdtar --numeric-owner --acls --xattrs --fflags -xpf "$rootfs_archive" -C "$root_mount"
install -d -m 0755 "$esp_mount"
mount "$esp_partition" "$esp_mount"
install -d -m 0755 "$esp_mount/EFI/BOOT"
install -m 0644 "$efi_binary" "$esp_mount/EFI/BOOT/BOOTAA64.EFI"

root_partuuid=$(blkid -s PARTUUID -o value "$root_partition")
esp_uuid=$(blkid -s UUID -o value "$esp_partition")
[[ -n "$root_partuuid" && -n "$esp_uuid" ]] || fail 'partition identifiers are unavailable'

install -d -m 0755 "$root_mount/boot/extlinux"
cat >"$root_mount/boot/extlinux/extlinux.conf" <<EOF
TIMEOUT 30
DEFAULT arch

MENU TITLE Omarchy Jetson Arch USB test

LABEL arch
      MENU LABEL Arch Linux ARM (Jetson kernel)
      LINUX /boot/Image-${kernel_release}
      INITRD /boot/initrd-${kernel_release}
      FDT /boot/dtb/tegra234-p3737-0000+p3701-0005-nv.dtb
      APPEND \${cbootargs} root=PARTUUID=${root_partuuid} rw rootwait rootfstype=ext4 console=ttyTCU0,115200 console=ttyAMA0,115200 console=tty0 firmware_class.path=/etc/firmware
EOF

cat >"$root_mount/etc/fstab" <<EOF
PARTUUID=${root_partuuid} / ext4 defaults,noatime 0 1
UUID=${esp_uuid} /boot/efi vfat umask=0077 0 2
EOF
printf 'omarchy-jetson\n' >"$root_mount/etc/hostname"

awk -F: -v user="$login_user" 'BEGIN {OFS=":"} $1=="alarm" {$1=user; $6="/home/" user} {print}' \
  "$root_mount/etc/passwd" >"$root_mount/etc/passwd.new"
awk -F: -v user="$login_user" 'BEGIN {OFS=":"} $1=="alarm" {$1=user; $2=""} {print}' \
  "$root_mount/etc/shadow" >"$root_mount/etc/shadow.new"
awk -F: -v user="$login_user" 'BEGIN {OFS=":"} $1=="alarm" {$1=user} {n=split($4,a,","); $4=""; for(i=1;i<=n;i++){if(a[i]=="alarm")a[i]=user; $4=$4 (i>1 ? "," : "") a[i]} print}' \
  "$root_mount/etc/group" >"$root_mount/etc/group.new"
awk -F: -v user="$login_user" 'BEGIN {OFS=":"} $1=="alarm" {$1=user} {n=split($4,a,","); $4=""; for(i=1;i<=n;i++){if(a[i]=="alarm")a[i]=user; $4=$4 (i>1 ? "," : "") a[i]} print}' \
  "$root_mount/etc/gshadow" >"$root_mount/etc/gshadow.new"
install -o 0 -g 0 -m 0644 "$root_mount/etc/passwd.new" "$root_mount/etc/passwd"
install -o 0 -g 0 -m 0600 "$root_mount/etc/shadow.new" "$root_mount/etc/shadow"
install -o 0 -g 0 -m 0644 "$root_mount/etc/group.new" "$root_mount/etc/group"
install -o 0 -g 0 -m 0600 "$root_mount/etc/gshadow.new" "$root_mount/etc/gshadow"
unlink "$root_mount/etc/passwd.new"
unlink "$root_mount/etc/shadow.new"
unlink "$root_mount/etc/group.new"
unlink "$root_mount/etc/gshadow.new"
mv "$root_mount/home/alarm" "$root_mount/home/$login_user"

install -d -o 1000 -g 1000 -m 0700 "$root_mount/home/$login_user/.ssh"
install -o 1000 -g 1000 -m 0600 "$ssh_public_key" \
  "$root_mount/home/$login_user/.ssh/authorized_keys"
chown -R 1000:1000 "$root_mount/home/$login_user"

install -d -m 0755 "$root_mount/etc/ssh/sshd_config.d"
cat >"$root_mount/etc/ssh/sshd_config.d/10-omarchy-jetson.conf" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF

[[ $(stat -c '%u:%g:%a' "$root_mount/etc/shadow") == 0:0:600 ]] || fail 'target shadow metadata is wrong'
[[ $(stat -c '%u:%g:%a' "$root_mount/usr/bin/bash") == 0:0:755 ]] || fail 'target system-file ownership is wrong'
[[ $(stat -c '%u:%g:%a' "$root_mount/home/$login_user/.ssh/authorized_keys") == 1000:1000:600 ]] || \
  fail 'target authorized_keys metadata is wrong'
[[ -s "$root_mount/boot/Image-$kernel_release" ]] || fail 'target kernel is missing'
[[ -s "$root_mount/boot/initrd-$kernel_release" ]] || fail 'target initrd is missing'
[[ -s "$root_mount/boot/dtb/tegra234-p3737-0000+p3701-0005-nv.dtb" ]] || fail 'target DTB is missing'
[[ -s "$esp_mount/EFI/BOOT/BOOTAA64.EFI" ]] || fail 'target EFI launcher is missing'
grep -qx "$login_user:x:1000:1000::/home/$login_user:/bin/bash" "$root_mount/etc/passwd" || \
  fail 'target login account is wrong'
grep -qx "$login_user::.*" "$root_mount/etc/shadow" || fail 'target key-only account state is wrong'
[[ ! -e "$root_mount/home/alarm" ]] || fail 'published default home remains'
[[ ! -s "$root_mount/etc/machine-id" ]] || fail 'target machine-id is already populated'
[[ $(find "$root_mount/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' | wc -l) == 0 ]] || \
  fail 'target already contains SSH host keys'

sync -f "$root_mount"
sync -f "$esp_mount"
pass 'USB filesystem contents and boot artifacts passed mounted-target validation'

umount "$esp_mount"
rmdir "$esp_mount"
umount "$root_mount"
rmdir "$root_mount"
esp_mount=
root_mount=

e2fsck -fn "$root_partition"
fsck.fat -vn "$esp_partition"
pass "USB test drive completed: $device"
