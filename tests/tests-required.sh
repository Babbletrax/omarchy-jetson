#!/usr/bin/env bash
# Fixture test for the pull-request gate ci/tests-required.sh: each case makes
# a throwaway repository, commits a change on a branch and checks the verdict.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
gate=$repo_root/ci/tests-required.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

git_() { git -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false "$@"; }

new_repo() {
  local d=$work/$1
  mkdir -p "$d"
  cd "$d"
  git_ init -q -b main
  mkdir -p packages/foo scripts tests docs config .github/workflows
  cat >packages/foo/PKGBUILD <<'EOF'
pkgname=foo
pkgver=1.0
pkgrel=1
source=('foo.sh'
        'https://example.com/foo-1.0.tar.gz')
sha256sums=('aaaa'
            'bbbb')
package() {
  install -Dm755 foo.sh "$pkgdir/usr/bin/foo"
}
EOF
  printf '#!/bin/sh\necho foo\n' >packages/foo/foo.sh
  printf '#!/bin/sh\necho build\n' >scripts/build.sh
  printf '#!/bin/sh\nexit 0\n' >tests/foo.sh
  printf '# Docs\n' >docs/guide.md
  printf 'name: x\n' >.github/workflows/x.yml
  printf 'opt=1\n' >config/settings.conf
  printf 'tool\n' >tool
  chmod +x scripts/build.sh tests/foo.sh packages/foo/foo.sh
  git_ add -A
  git_ commit -qm base
  git_ switch -qc change
}

# expect NAME EXIT-CODE [ENV...]: run the gate on the current fixture repo.
expect() {
  local name=$1 want=$2 got=0 out
  shift 2
  out=$(env "$@" "$gate" main 2>&1) || got=$?
  if [[ $got == "$want" ]]; then
    printf 'PASS  tests-required: %s\n' "$name"
  else
    printf 'FAIL  tests-required: %s (exit %s, want %s)\n%s\n' "$name" "$got" "$want" "$out" >&2
    failures=$((failures + 1))
  fi
}

commit() { git_ add -A && git_ commit -qm change; }

new_repo docs-only
printf 'more\n' >>docs/guide.md
printf 'readme\n' >README.md
commit
expect 'docs and Markdown only' 0

new_repo workflow-only
printf 'on: push\n' >>.github/workflows/x.yml
commit
expect 'workflow only' 0

new_repo script-no-test
printf 'echo more\n' >>scripts/build.sh
commit
expect 'script change without a test fails' 1

new_repo script-with-test
printf 'echo more\n' >>scripts/build.sh
printf 'echo checked\n' >>tests/foo.sh
commit
expect 'script change with a modified test' 0

new_repo script-new-test
printf 'echo more\n' >>scripts/build.sh
printf '#!/bin/sh\n' >tests/new.sh
commit
expect 'script change with a new test' 0

new_repo deleted-test-only
printf 'echo more\n' >>scripts/build.sh
git_ rm -q tests/foo.sh
commit
expect 'deleting a test does not count as testing' 1

new_repo package-file
printf 'echo bar\n' >>packages/foo/foo.sh
commit
expect 'packaged file change without a test fails' 1

new_repo bump-only
sed -i -e 's/^pkgver=1.0/pkgver=1.1/' -e 's/^pkgrel=1/pkgrel=2/' -e 's/aaaa/cccc/' -e 's/bbbb/dddd/' packages/foo/PKGBUILD
commit
expect 'pkgver/pkgrel/checksum bump is exempt' 0

new_repo pkgbuild-logic
sed -i 's/install -Dm755/install -Dm775/' packages/foo/PKGBUILD
commit
expect 'PKGBUILD logic change without a test fails' 1

new_repo pkgbuild-source
sed -i "s#'foo.sh'#'foo.sh' 'extra.conf'#" packages/foo/PKGBUILD
sed -i 's/pkgrel=1/pkgrel=2/' packages/foo/PKGBUILD
commit
expect 'PKGBUILD source change with a bump still needs a test' 1

new_repo config
printf 'opt=2\n' >config/settings.conf
commit
expect 'config change without a test fails' 1

new_repo executable
printf 'more\n' >>tool
chmod +x tool
commit
expect 'executable file without extension fails' 1

new_repo python
printf 'print(1)\n' >helper.py
commit
expect 'new Python file without a test fails' 1

new_repo waiver
printf 'echo more\n' >>scripts/build.sh
commit
summary_file=$work/summary.md
expect 'no-tests-needed label waives the gate' 0 "PR_LABELS=bug,no-tests-needed" "GITHUB_STEP_SUMMARY=$summary_file"
if grep -q 'Waived' "$summary_file" && grep -q 'scripts/build.sh' "$summary_file"; then
  printf 'PASS  tests-required: waiver recorded in the job summary\n'
else
  printf 'FAIL  tests-required: waiver not recorded in the job summary\n' >&2
  failures=$((failures + 1))
fi
expect 'a similar label does not waive' 1 "PR_LABELS=no-tests-needed-later"

new_repo dependabot
printf 'echo more\n' >>scripts/build.sh
commit
expect 'Dependabot is exempt' 0 'PR_AUTHOR=dependabot[bot]'
expect 'other authors are not' 1 'PR_AUTHOR=someone'

((failures == 0)) || exit 1
