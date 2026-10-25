#!/usr/bin/env bash
# Arch Linux ARM build container for CI on an AArch64 Docker host.
#
# Arch Linux ARM publishes no official Docker image, so this one is made from
# the official rootfs tarball, accepted only after its detached signature
# verifies against the Arch Linux ARM build key committed in ci/keys/ and
# pinned by fingerprint (ARCH_ROOTFS_SIGNING_KEY in config/versions.env), and
# its published MD5 matches. No third-party image is pulled.
#
#   ci/alarm-container.sh build          create the image ($ALARM_IMAGE)
#   ci/alarm-container.sh run CMD...     run CMD as root in it, checkout at /src
#
# Inside the image: pacman with the Arch Linux ARM repos and upstream Omarchy's
# [omarchy] repo (its key pinned the same way), pacman's download sandbox off
# (Docker's seccomp profile blocks it; the container is the sandbox), and an
# unprivileged `builder` user for makepkg.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image=${ALARM_IMAGE:-omarchy-jetson-alarm:ci}
docker=${DOCKER:-docker}
# shellcheck disable=SC1091
source "$repo_root/config/versions.env"

packages=(base-devel git jq ripgrep python file xz rsync namcap sudo)

build() {
  local work tarball
  work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/alarm.XXXXXX")
  trap 'rm -rf "$work"' RETURN
  tarball=$work/${ARCH_ROOTFS_URL##*/}

  # The publisher serves these over HTTP only (see config/inputs.lock.json);
  # the OpenPGP signature is what makes the download trustworthy.
  curl -fsSL --retry 3 -o "$tarball" "$ARCH_ROOTFS_URL"
  curl -fsSL --retry 3 -o "$tarball.sig" "$ARCH_ROOTFS_SIGNATURE_URL"
  curl -fsSL --retry 3 -o "$tarball.md5" "$ARCH_ROOTFS_URL.md5"
  "$repo_root/ci/verify-signature.sh" "$repo_root/ci/keys/archlinuxarm-build.asc" \
    "$ARCH_ROOTFS_SIGNING_KEY" "$tarball.sig" "$tarball"
  (cd "$work" && sed -E "s#[[:space:]]+.*#  ${tarball##*/}#" "$tarball.md5" | md5sum -c --quiet -)

  $docker import -c 'ENV LANG=C.UTF-8' -c 'CMD ["/bin/bash"]' "$tarball" "$image-base" >/dev/null
  rm -f "$tarball"

  local setup
  setup=$(
    cat <<EOF
set -Eeuo pipefail
sed -i -e 's/^\[options\]\$/[options]\nDisableSandbox/' -e 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm >/dev/null 2>&1
# Upstream Omarchy's repository, trusted through the pinned key only.
pacman-key --add /src/ci/keys/omarchy.asc >/dev/null 2>&1
pacman-key --lsign-key '$OMARCHY_SIGNING_KEY' >/dev/null 2>&1
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
  printf '\n[omarchy]\nServer = %s/\$arch\n' '$OMARCHY_PACKAGE_REPOSITORY' >>/etc/pacman.conf
fi
pacman -Syu --noconfirm --needed ${packages[*]} >/dev/null
useradd -m -U builder
echo 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' >/etc/sudoers.d/builder
chmod 0440 /etc/sudoers.d/builder
pacman -Scc --noconfirm >/dev/null
pacman -Q pacman namcap | sed 's/^/  /'
EOF
  )
  local name=alarm-setup-$$
  $docker rm -f "$name" >/dev/null 2>&1 || true
  $docker run --name "$name" -v "$repo_root:/src:ro" "$image-base" bash -c "$setup"
  $docker commit -c 'ENV LANG=C.UTF-8' "$name" "$image" >/dev/null
  $docker rm "$name" >/dev/null
  $docker rmi "$image-base" >/dev/null
  echo "built $image"
}

run() {
  local env_args=() v
  # Pass through only the variables the CI scripts read.
  for v in BUILD_ALL BASE_SHA GITHUB_STEP_SUMMARY; do
    [[ -n ${!v:-} ]] && env_args+=(-e "$v=${!v}")
  done
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    env_args+=(-v "$GITHUB_STEP_SUMMARY:$GITHUB_STEP_SUMMARY")
  fi
  $docker run --rm "${env_args[@]}" -v "$repo_root:/src" -w /src "$image" bash -c "$*"
}

case ${1:-} in
  build) build ;;
  run)
    shift
    run "$@"
    ;;
  *)
    echo "usage: $0 build | run CMD..." >&2
    exit 2
    ;;
esac
