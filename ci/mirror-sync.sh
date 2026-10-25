#!/usr/bin/env bash
# Two-way, fast-forward-only sync of a branch (and tags) between two remotes,
# e.g. the GitLab project and its public GitHub mirror. Changes can land on
# either side (GitLab merge requests, GitHub pull requests); whichever side is
# ahead is fast-forwarded onto the other. If both moved, it stops and fails so
# a person merges, instead of guessing.
#
#   ci/mirror-sync.sh PRIMARY_URL PUBLIC_URL [BRANCH]
#
# PRIMARY is the private-side remote (GitLab), PUBLIC the published one
# (GitHub). Before anything is pushed to PUBLIC, the commits about to be
# published are checked: the public-hygiene scan (with private patterns when
# HYGIENE_PRIVATE_FILE or HYGIENE_PRIVATE_PATTERNS is set) and gitleaks over
# exactly that range. Tags are copied in both directions but never moved or
# deleted. Credentials come in the URLs from CI variables; nothing is printed.
#
# Environment: MIRROR_DRY_RUN=1 reports what would happen without pushing.
set -Eeuo pipefail

primary=${1:?usage: $0 PRIMARY_URL PUBLIC_URL [BRANCH]}
public=${2:?usage: $0 PRIMARY_URL PUBLIC_URL [BRANCH]}
branch=${3:-main}
dry=${MIRROR_DRY_RUN:-0}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q --bare "$work/repo.git"
g() { git --git-dir="$work/repo.git" "$@"; }
say() { printf '%s\n' "$*"; }
# Never echo a URL: it may carry a token.
redact() { sed -E 's#(https?://)[^@/]+@#\1***@#g'; }

g remote add primary "$primary"
g remote add public "$public"
g fetch -q --no-tags primary "+refs/heads/$branch:refs/remotes/primary/$branch" "+refs/tags/*:refs/tags/primary/*" 2>&1 | redact
g fetch -q --no-tags public "+refs/heads/$branch:refs/remotes/public/$branch" "+refs/tags/*:refs/tags/public/*" 2>&1 | redact || true

p=$(g rev-parse -q --verify "refs/remotes/primary/$branch") || {
  say "primary has no $branch"
  exit 1
}
q=$(g rev-parse -q --verify "refs/remotes/public/$branch" || true)

push() {
  local remote=$1 ref=$2
  if [[ $dry == 1 ]]; then
    say "dry-run: would push $ref to $remote"
    return
  fi
  g push -q "$remote" "$ref" 2>&1 | redact
}

# Publishing gate: what goes to the public side is scanned first.
# Every commit in the range is scanned, not just the tip: history is
# published too, so something added and later removed still counts. Each
# commit is held to today's rules: the scanners and their allow lists come
# from the tip being published, not from the (possibly older) commit.
scanners=(tests/public-hygiene.sh tests/public-hygiene.allow tests/no-hardcoded-config.py tests/no-hardcoded-config.allow)
gate() {
  local from=$1 to=$2 tree range c f
  if [[ -n $from ]]; then range="$from..$to"; else range=$to; fi
  while read -r c; do
    # A fresh directory per commit, inside $work (removed on exit).
    tree=$(mktemp -d "$work/tree.XXXXXX")
    g --work-tree="$tree" checkout -q "$c" -- .
    mkdir -p "$tree/tests"
    for f in "${scanners[@]}"; do
      g show "$to:$f" >"$tree/$f" 2>/dev/null || rm -f "$tree/$f"
    done
    chmod +x "$tree"/tests/*.sh "$tree"/tests/*.py 2>/dev/null || true
    (cd "$tree" && ./tests/public-hygiene.sh && ./tests/no-hardcoded-config.py) >/dev/null 2>&1 ||
      {
        say "hygiene failed on commit $c: not publishing"
        return 1
      }
  done < <(g rev-list --reverse "$range")
  if command -v gitleaks >/dev/null; then
    gitleaks git --redact --no-banner --log-opts="$range" --exit-code 1 "$work/repo.git" >/dev/null 2>&1 ||
      {
        say "gitleaks found something in $range: not publishing"
        return 1
      }
  else
    say "gitleaks not installed: not publishing"
    return 1
  fi
}

if [[ -z $q ]]; then
  say "public has no $branch yet: publishing $p"
  gate "" "$p"
  push public "$p:refs/heads/$branch"
elif [[ $p == "$q" ]]; then
  say "$branch in sync at $p"
elif g merge-base --is-ancestor "$q" "$p"; then
  say "primary is ahead: fast-forwarding public $q..$p"
  gate "$q" "$p"
  push public "$p:refs/heads/$branch"
elif g merge-base --is-ancestor "$p" "$q"; then
  say "public is ahead: fast-forwarding primary $p..$q"
  push primary "$q:refs/heads/$branch"
else
  say "DIVERGED: primary $p and public $q both have new commits on $branch."
  say "Merge one into the other (e.g. merge the GitHub side into a GitLab MR), then the next sync fast-forwards."
  exit 3
fi

# Tags: copy ones missing on a side; a tag that differs between sides is an
# error to report, never something to overwrite.
status=0
while read -r tag; do
  [[ -n $tag ]] || continue
  a=$(g rev-parse -q --verify "refs/tags/primary/$tag^{}" || true)
  b=$(g rev-parse -q --verify "refs/tags/public/$tag^{}" || true)
  if [[ -n $a && -z $b ]]; then
    gate "" "$a" && push public "refs/tags/primary/$tag:refs/tags/$tag"
  elif [[ -z $a && -n $b ]]; then
    push primary "refs/tags/public/$tag:refs/tags/$tag"
  elif [[ $a != "$b" ]]; then
    say "tag $tag differs between the sides: left alone"
    status=4
  fi
done < <(g for-each-ref --format='%(refname)' refs/tags/primary refs/tags/public |
  sed -E 's#^refs/tags/(primary|public)/##' | sort -u)
exit $status
