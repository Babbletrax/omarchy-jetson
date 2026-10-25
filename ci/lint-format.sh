#!/usr/bin/env bash
# Formatting checks: shfmt for shell and `ruff format` for Python, in diff mode.
#
#   ci/lint-format.sh [BASE | --all]
#
# The existing tree predates these checks and is not formatter-clean, so only
# the files changed since the merge base with BASE are checked: new and edited
# code gets formatted, untouched code is left alone. BASE defaults to HEAD~1
# (also used when BASE is all zeros or unknown, as for a new or force-pushed
# branch); --all checks every file. shfmt uses the style the existing scripts follow:
# two-space indents and indented case branches (-i 2 -ci).
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
shfmt_flags=(-i 2 -ci)

mapfile -t shell < <(shfmt -f . | grep -v '^\.git/' | sort)
mapfile -t python < <(git ls-files '*.py' | sort)

if [[ ${1:-} != --all ]]; then
  base=${1:-}
  if [[ -z $base || $base =~ ^0+$ ]] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    base=HEAD~1
  fi
  base=$(git merge-base "$base" HEAD)
  mapfile -t changed < <(git diff --name-only --diff-filter=d "$base" HEAD | sort)
  filter() { comm -12 <(printf '%s\n' "${@:2}" | sed '/^$/d' | sort) <(printf '%s\n' "${changed[@]}" | sed '/^$/d'); }
  mapfile -t shell < <(filter x "${shell[@]}")
  mapfile -t python < <(filter x "${python[@]}")
  scope="changed since ${base:0:12}"
else
  scope=all
fi

fail=0
if ((${#shell[@]})); then
  if shfmt "${shfmt_flags[@]}" -d "${shell[@]}"; then
    printf 'PASS  shfmt %s (%d %s shell files)\n' "${shfmt_flags[*]}" "${#shell[@]}" "$scope"
  else
    printf 'FAIL  shfmt: run shfmt %s -w on the files above\n' "${shfmt_flags[*]}" >&2
    fail=1
  fi
else
  printf 'PASS  shfmt (no %s shell files)\n' "$scope"
fi
if ((${#python[@]})); then
  if ruff format --check --diff "${python[@]}"; then
    printf 'PASS  ruff format (%d %s Python files)\n' "${#python[@]}" "$scope"
  else
    printf 'FAIL  ruff format: run ruff format on the files above\n' >&2
    fail=1
  fi
else
  printf 'PASS  ruff format (no %s Python files)\n' "$scope"
fi
exit $fail
