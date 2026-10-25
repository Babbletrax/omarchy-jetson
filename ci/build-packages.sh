#!/usr/bin/env bash
# Build changed (or all) packages/<name> with makepkg as the unprivileged
# builder user, and run namcap on each result. Runs as root inside the Arch
# Linux ARM container (ci/alarm-container.sh run ci/build-packages.sh).
#
#   BUILD_ALL=true   build every package (push to main, schedule, manual run)
#   BASE_SHA=<sha>   otherwise build the packages changed since its merge base
#                    with HEAD (default: HEAD~1)
#
# Packages that depend on other packages in this repository (e.g. the
# development bundle on nvidia-jetson-cuda and visual-studio-code-bin) get
# those built first, and installable from a local repository.
set -Eeuo pipefail

repo=$(pwd)
out=$repo/ci-out
localrepo=/tmp/ci-repo
mkdir -p "$out" "$localrepo"
# The checkout belongs to the runner, not this container's root.
git config --global --add safe.directory "$repo"

all=false
[[ ${BUILD_ALL:-false} == true ]] && all=true

# pkgname and in-repo dependencies of a package directory.
pkg_field() {
  (cd "packages/$1" && JETSON_BSP_DIR=/nonexistent JETSON_INITRD=/nonexistent startdir=$PWD bash -c '
    source ./PKGBUILD >/dev/null 2>&1
    case $0 in
      names) printf "%s\n" "${pkgname[@]}" ;;
      deps) printf "%s\n" "${depends[@]}" "${makedepends[@]}" | sed -E "s/[<>=].*//" ;;
    esac' "$2")
}

declare -A dir_of=()
for d in packages/*/; do
  d=${d%/}
  d=${d#packages/}
  [[ -f packages/$d/PKGBUILD ]] || continue
  while read -r n; do [[ -n $n ]] && dir_of[$n]=$d; done < <(pkg_field "$d" names)
done

if $all; then
  mapfile -t wanted < <(printf '%s\n' "${dir_of[@]}" | sort -u)
else
  # Diff against the merge base with the target (the checkout needs the full
  # history). A failed diff must fail the job, not look like "no changes".
  if [[ -n ${BASE_SHA:-} && ! ${BASE_SHA} =~ ^0+$ ]]; then
    base=$(git merge-base "$BASE_SHA" HEAD)
  else
    base=$(git rev-parse HEAD~1)
  fi
  changed=$(git diff --name-only "$base" HEAD -- packages)
  mapfile -t wanted < <(
    cut -d/ -f2 <<<"$changed" | sort -u |
      while read -r d; do [[ -n $d && -f packages/$d/PKGBUILD ]] && echo "$d"; done
  )
fi

if ((${#wanted[@]} == 0)); then
  echo "No package changes."
  exit 0
fi

# Depth-first: a package's in-repo dependencies come before it.
order=()
declare -A seen=()
visit() {
  local d=$1 dep
  [[ -n ${seen[$d]:-} ]] && return
  seen[$d]=1
  while read -r dep; do
    [[ -n $dep && -n ${dir_of[$dep]:-} && ${dir_of[$dep]} != "$d" ]] && visit "${dir_of[$dep]}"
  done < <(pkg_field "$d" deps)
  order+=("$d")
}
for d in "${wanted[@]}"; do visit "$d"; done

# Built packages go into a local repository, so makepkg --syncdeps finds them.
repo-add -q "$localrepo/ci-local.db.tar.gz" >/dev/null 2>&1 || true
if ! grep -q '^\[ci-local\]' /etc/pacman.conf; then
  printf '\n[ci-local]\nSigLevel = Never\nServer = file://%s\n' "$localrepo" >>/etc/pacman.conf
fi
# One full sync up front, retried: a stalled mirror shouldn't fail the build.
for attempt in 1 2 3; do
  pacman -Sy >/dev/null && break
  ((attempt == 3)) && exit 1
  sleep $((attempt * 20))
done
# After each build only the local repository changes; refresh just that
# (pacman reads file:// databases straight into its sync directory).
refresh_local() {
  cp "$localrepo/ci-local.db.tar.gz" "$(pacman-conf DBPath)sync/ci-local.db"
}

# PKGBUILDs read files relative to $startdir (../../LICENSE, config/...), so
# they build in place; the build tree and results go outside the checkout.
chown -R builder: "$repo"
fail=0
summary=()
declare -A failed=()
for name in "${order[@]}"; do
  src=packages/$name
  if grep -qE 'JETSON_(BSP_DIR|INITRD)' "$src/PKGBUILD"; then
    echo "SKIP  $name (needs the NVIDIA BSP tree or a generated initrd)"
    summary+=("| $name | skipped: needs the NVIDIA BSP tree |")
    failed[$name]=skipped
    continue
  fi
  blocked=
  while read -r dep; do
    [[ -n $dep && -n ${dir_of[$dep]:-} && -n ${failed[${dir_of[$dep]}]:-} ]] && blocked=${dir_of[$dep]}
  done < <(pkg_field "$name" deps)
  if [[ -n $blocked ]]; then
    if [[ ${failed[$blocked]} == skipped ]]; then
      echo "SKIP  $name (depends on $blocked, which CI can't build)"
      summary+=("| $name | skipped: needs $blocked |")
      failed[$name]=skipped
    else
      echo "FAIL  $name (depends on $blocked, which failed)"
      summary+=("| $name | **failed**: $blocked failed |")
      failed[$name]=failed
      fail=1
    fi
    continue
  fi
  echo "::: $name"
  dest=$out/$name
  install -d -o builder "$dest"
  if su builder -c "cd '$repo/$src' && BUILDDIR=/tmp/build-$name PKGDEST='$dest' SRCDEST=/tmp/src-$name makepkg --syncdeps --noconfirm --cleanbuild" >"$out/$name.log" 2>&1; then
    for pkg in "$dest"/*.pkg.tar.*; do
      # namcap is advisory: vendored NVIDIA/vendor binaries trip many rules.
      # Full output is in the job artifacts; the log gets a count.
      report="$dest/$(basename "$pkg").namcap"
      namcap "$pkg" >"$report" 2>&1 || true
      printf '      namcap %s: %s errors, %s warnings\n' "$(basename "$pkg")" \
        "$(grep -c ' E: ' "$report" || true)" "$(grep -c ' W: ' "$report" || true)"
      cp "$pkg" "$localrepo/"
      repo-add -q "$localrepo/ci-local.db.tar.gz" "$localrepo/$(basename "$pkg")" >/dev/null
    done
    refresh_local
    echo "PASS  $name"
    summary+=("| $name | built |")
  else
    tail -40 "$out/$name.log"
    echo "FAIL  $name (full log in ci-out/$name.log)"
    summary+=("| $name | **failed** |")
    failed[$name]=failed
    fail=1
  fi
done
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  printf '### Package builds\n\n| package | result |\n| --- | --- |\n%s\n' "$(printf '%s\n' "${summary[@]}")" >>"$GITHUB_STEP_SUMMARY"
fi
exit $fail
