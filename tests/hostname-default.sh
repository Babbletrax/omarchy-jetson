#!/usr/bin/env bash
# `omarchy-jetson` is only the default hostname: it is seeded once, when a new
# system image is written, and never owned or rewritten by a package or an
# update, so a user's own hostname survives `omarchy-update`.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
seeder=scripts/write-usb-test-drive.sh
failures=0
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Writes to the hostname: the file itself, hostnamectl, or the kernel knob.
writes='etc/hostname|hostnamectl[[:space:]]+(set-hostname|hostname)|kernel[./]hostname|\bhostname[[:space:]]+-[bF]|\bhostname[[:space:]]+[a-z0-9$"]'

# 1. No package ships, backs up or touches /etc/hostname, in its PKGBUILD,
#    install script, hooks, units or any other packaged file.
if hits=$(rg -n --hidden -e "$writes" packages); then
  fail "a package owns or writes the hostname:"
  printf '%s\n' "$hits" >&2
else
  printf 'PASS  no package owns or writes /etc/hostname\n'
fi

# 2. Nothing else that runs on an installed system (update, release channel,
#    rootfs config, recovery) writes it; only the image writer may seed it.
if hits=$(rg -n --hidden -e "$writes" scripts config recovery --glob "!${seeder#scripts/}" --glob '!config/rootfs/hostname'); then
  fail "an update or build path writes the hostname:"
  printf '%s\n' "$hits" >&2
else
  printf 'PASS  only %s seeds the hostname\n' "$seeder"
fi

# 3. The image writer seeds it exactly once, into the new image's root, with
#    the documented default.
mapfile -t seeds < <(rg -n 'etc/hostname' "$seeder")
if ((${#seeds[@]} == 1)) && [[ ${seeds[0]} == *"printf 'omarchy-jetson\\n' >\"\$root_mount/etc/hostname\""* ]]; then
  printf 'PASS  image creation seeds the default hostname once\n'
else
  fail "$seeder must seed \$root_mount/etc/hostname exactly once with omarchy-jetson (found ${#seeds[@]})"
fi

# 4. The reference copy in config/rootfs matches and is not packaged.
if [[ $(<config/rootfs/hostname) == omarchy-jetson ]] && ! rg -q 'rootfs/hostname' packages scripts; then
  printf 'PASS  config/rootfs/hostname is the unpackaged default\n'
else
  fail 'config/rootfs/hostname must hold the default and not be packaged'
fi

((failures == 0)) || exit 1
