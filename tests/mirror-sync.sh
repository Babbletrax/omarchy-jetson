#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fx=$(mktemp -d)
trap 'rm -rf "$fx"' EXIT
sync=$repo_root/ci/mirror-sync.sh

# A stand-in gitleaks: clean unless the range touches a file named LEAK.
mkdir -p "$fx/bin"
cat >"$fx/bin/gitleaks" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do case $a in --log-opts=*) range=${a#--log-opts=} ;; esac; done
dir=${!#}
git --git-dir="$dir" log --name-only --format= $range | grep -qx LEAK && exit 1
exit 0
SH
chmod +x "$fx/bin/gitleaks"
export PATH="$fx/bin:$PATH" HYGIENE_PRIVATE_PATTERNS='' GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com HYGIENE_PRIVATE_FILE=/nonexistent

git init -q --bare -b main "$fx/primary.git"
git init -q --bare -b main "$fx/public.git"
git init -q -b main "$fx/w"
# Seed with this repository's working tree, so the real hygiene scans run.
(cd "$repo_root" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -c) | tar -x -C "$fx/w"
git -C "$fx/w" add -A && git -C "$fx/w" commit -qm seed
git -C "$fx/w" push -q "$fx/primary.git" main

head_of() { git --git-dir="$1" rev-parse -q --verify refs/heads/main || true; }
commit() { (cd "$fx/w" && printf '%s\n' "$2" >"$1" && git add "$1" && git commit -qm "$1"); }
run() { "$sync" "$fx/primary.git" "$fx/public.git" main; }

# 1. First publish.
out=$(run)
[[ $out == *"publishing"* ]]
[[ $(head_of "$fx/public.git") == "$(head_of "$fx/primary.git")" ]]

# 2. Primary ahead: fast-forwards public.
commit notes.md 'a note'
git -C "$fx/w" push -q "$fx/primary.git" main
out=$(run)
[[ $out == *"primary is ahead"* ]]
[[ $(head_of "$fx/public.git") == "$(head_of "$fx/primary.git")" ]]

# 3. Public ahead (a merged pull request): fast-forwards primary.
git clone -q "$fx/public.git" "$fx/gh"
(cd "$fx/gh" && printf 'pr\n' >pr.md && git add pr.md && git commit -qm pr && git push -q origin main)
out=$(run)
[[ $out == *"public is ahead"* ]]
[[ $(head_of "$fx/primary.git") == "$(head_of "$fx/public.git")" ]]
git -C "$fx/w" pull -q "$fx/primary.git" main

# 4. A private address on the primary side is never published.
# Built at run time so this file itself doesn't trip the hygiene scan.
commit private.md "reach it at $(printf '%s.%s.%s.%s' 192 168 1 20)"
git -C "$fx/w" push -q "$fx/primary.git" main
before=$(head_of "$fx/public.git")
if out=$(run); then exit 1; fi
[[ $(head_of "$fx/public.git") == "$before" ]]
# Removing it again isn't enough: the commit that added it is still in the
# history being published, so it stays blocked until that history is rewritten.
git -C "$fx/w" rm -q private.md && git -C "$fx/w" commit -qm 'drop it'
git -C "$fx/w" push -q "$fx/primary.git" main
if out=$(run); then exit 1; fi
[[ $out == *"hygiene failed on commit"* ]]
[[ $(head_of "$fx/public.git") == "$before" ]]
git -C "$fx/w" reset -q --hard HEAD~2
git -C "$fx/w" push -q -f "$fx/primary.git" main

# 5. A secret in the range is never published.
commit LEAK 'token'
git -C "$fx/w" push -q "$fx/primary.git" main
if out=$(run); then exit 1; fi
[[ $(head_of "$fx/public.git") == "$before" ]]
git -C "$fx/w" reset -q --hard HEAD~1
git -C "$fx/w" push -q -f "$fx/primary.git" main

# 6. Both sides moved: stop with exit 3, push nothing.
commit gl.md 'gitlab side'
git -C "$fx/w" push -q "$fx/primary.git" main
(cd "$fx/gh" && git pull -q && printf 'x\n' >gh.md && git add gh.md && git commit -qm gh && git push -q origin main)
p0=$(head_of "$fx/primary.git") q0=$(head_of "$fx/public.git")
set +e
out=$(run)
rc=$?
set -e
[[ $rc == 3 && $out == *DIVERGED* ]]
[[ $(head_of "$fx/primary.git") == "$p0" && $(head_of "$fx/public.git") == "$q0" ]]

# 7. Tags copy both ways, and a tag that differs is left alone.
git --git-dir="$fx/public.git" tag v1 "$q0"
git --git-dir="$fx/primary.git" tag v0 "$(git --git-dir="$fx/primary.git" rev-parse "$p0~1")"
git --git-dir="$fx/primary.git" tag clash "$p0"
git --git-dir="$fx/public.git" tag clash "$q0"
set +e
out=$(run)
rc=$?
set -e
[[ $rc == 3 ]] # still diverged; branch handling stops before tags
git -C "$fx/w" pull -q --no-rebase "$fx/public.git" main && git -C "$fx/w" push -q "$fx/primary.git" main
set +e
out=$(run)
rc=$?
set -e
[[ $rc == 4 && $out == *"tag clash differs"* ]]
git --git-dir="$fx/primary.git" rev-parse -q --verify refs/tags/v1 >/dev/null
git --git-dir="$fx/public.git" rev-parse -q --verify refs/tags/v0 >/dev/null

printf 'PASS  two-way mirror sync: fast-forwards either way, gates publishing, stops on divergence\n'
