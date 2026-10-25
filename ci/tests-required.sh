#!/usr/bin/env bash
# Pull-request gate: a change to functional code must add or change a test.
#
#   ci/tests-required.sh BASE [HEAD]
#
# Compares HEAD (default HEAD) with its merge base with BASE. Functional code is
# anything under packages/, scripts/, ci/, config/, recovery/ or patches/, the
# Makefile, any *.sh or *.py file and any executable file. Exempt: Markdown and
# docs/, .github/ (workflows, templates, Dependabot), and PKGBUILD edits that
# only bump pkgver, pkgrel or checksums. A change passes when it touches
# nothing functional, or adds or modifies a file under tests/.
#
# Environment:
#   PR_LABELS   newline- or comma-separated labels; `no-tests-needed`, which
#               only a maintainer can apply, waives the gate (and says so)
#   PR_AUTHOR   `dependabot[bot]` is exempt (version bumps only)
#   GITHUB_STEP_SUMMARY   when set, the verdict is appended there too
# shellcheck disable=SC2016 # backticks below are Markdown, not expansions
set -Eeuo pipefail

base=${1:?usage: $0 BASE [HEAD]}
head=${2:-HEAD}
waiver=no-tests-needed

summary() { [[ -n ${GITHUB_STEP_SUMMARY:-} ]] && printf '%s\n' "$@" >>"$GITHUB_STEP_SUMMARY" || true; }

merge_base=$(git merge-base "$base" "$head")

# Is a PKGBUILD change only a version/release/checksum bump? Compare both sides
# with those assignments (including multi-line checksum arrays) removed.
strip_bumps() {
  awk '
    in_sums { if ($0 ~ /\)[[:space:]]*(#.*)?$/) in_sums = 0; next }
    /^(pkgver|pkgrel|epoch)=/ { next }
    /^[a-z0-9]*sums(_[a-z0-9_]+)?=\(/ { if ($0 !~ /\)[[:space:]]*(#.*)?$/) in_sums = 1; next }
    { print }
  '
}
bump_only() { # path
  local old new
  old=$(git show "$merge_base:$1" 2>/dev/null | strip_bumps) || return 1
  new=$(git show "$head:$1" 2>/dev/null | strip_bumps) || return 1
  [[ $old == "$new" ]]
}

is_functional() { # status path
  local status=$1 path=$2 mode
  case $path in
    tests/*) return 1 ;;
    *.md | docs/* | .github/* | LICENSE | .gitignore | .gitleaks.toml) return 1 ;;
  esac
  case $path in
    packages/*/PKGBUILD)
      [[ $status == M ]] && bump_only "$path" && return 1
      return 0
      ;;
    packages/* | scripts/* | ci/* | config/* | recovery/* | patches/* | Makefile | *.sh | *.py) return 0 ;;
  esac
  # Any other executable file (deleted files have no new mode).
  if [[ $status != D ]]; then
    mode=$(git ls-tree "$head" -- "$path" | awk '{print $1}')
    [[ $mode == 100755 ]] && return 0
  fi
  return 1
}

functional=()
tests_changed=()
bumps=()
# --no-renames: a move is a deletion plus an addition, so both paths count.
while IFS=$'\t' read -r status path; do
  if [[ $path == tests/* ]]; then
    [[ $status != D ]] && tests_changed+=("$path")
    continue
  fi
  if is_functional "$status" "$path"; then
    functional+=("$path")
  elif [[ $path == packages/*/PKGBUILD ]]; then
    bumps+=("$path")
  fi
done < <(git diff --no-renames --name-status "$merge_base" "$head")

labels=$(tr ',' '\n' <<<"${PR_LABELS:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

summary '### Tests required'
if ((${#bumps[@]})); then
  printf 'note: version/checksum-only bumps (exempt): %s\n' "${bumps[*]}"
fi
if ((${#functional[@]} == 0)); then
  echo "PASS  no functional code changed"
  summary 'No functional code changed.'
  exit 0
fi
if ((${#tests_changed[@]})); then
  printf 'PASS  %d functional file(s) changed with %d test file(s)\n' "${#functional[@]}" "${#tests_changed[@]}"
  summary "${#functional[@]} functional file(s) changed, with tests: $(printf '`%s` ' "${tests_changed[@]}")"
  exit 0
fi
if [[ ${PR_AUTHOR:-} == 'dependabot[bot]' ]]; then
  echo "PASS  Dependabot version bump"
  summary 'Dependabot version bump: exempt.'
  exit 0
fi
if grep -qxF "$waiver" <<<"$labels"; then
  printf 'WAIVED  functional change without tests, label %s applied:\n' "$waiver"
  printf '  %s\n' "${functional[@]}"
  summary "**Waived** by the \`$waiver\` label. Functional files changed without tests:" \
    "$(printf -- '- `%s`\n' "${functional[@]}")"
  exit 0
fi

printf 'FAIL  functional code changed without a test under tests/:\n' >&2
printf '  %s\n' "${functional[@]}" >&2
printf 'Add or extend a test in tests/ (and register it in the Makefile), or ask a\n' >&2
printf 'maintainer to apply the %s label if no test can cover the change.\n' "$waiver" >&2
summary "**Failed**: functional files changed without a test under \`tests/\`:" \
  "$(printf -- '- `%s`\n' "${functional[@]}")"
exit 1
