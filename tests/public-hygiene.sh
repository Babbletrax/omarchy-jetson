#!/usr/bin/env bash
# Public-repository hygiene gate.
#
# Fails when the tree contains things that must not be published: private
# hostnames or names, RFC 1918 addresses, personal e-mail addresses, vendored
# binary packages or large blobs, 1Password references, or maintainer-specific
# names supplied privately (see section 1).
#
# Known-good exceptions go in tests/public-hygiene.allow as `path:regex` lines,
# where `path` is a file path or bash glob and `regex` (ERE) must match the
# offending line. This script and its allow file are not content-scanned
# because they necessarily contain the patterns.
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

allow_file=tests/public-hygiene.allow
max_bytes=$((2 * 1024 * 1024))
failures=0

# --- file list -------------------------------------------------------------
files=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    [[ -f $f ]] && files+=("$f")
  done < <(git ls-files -z --cached --others --exclude-standard)
else
  while IFS= read -r -d '' f; do
    files+=("${f#./}")
  done < <(find . -path ./.git -prune -o -type f -print0)
fi

scan_files=()
for f in "${files[@]}"; do
  case $f in
    tests/public-hygiene.sh | "$allow_file") ;;
    *) scan_files+=("$f") ;;
  esac
done

# --- allowlist ---------------------------------------------------------------
allow_paths=()
allow_regexes=()
if [[ -f $allow_file ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    allow_paths+=("${line%%:*}")
    allow_regexes+=("${line#*:}")
  done <"$allow_file"
fi

allowed() { # path, line-content
  local i
  for i in "${!allow_paths[@]}"; do
    # shellcheck disable=SC2053 # allow-file paths are deliberate globs
    if [[ $1 == ${allow_paths[i]} ]] && grep -qE -- "${allow_regexes[i]}" <<<"$2"; then
      return 0
    fi
  done
  return 1
}

report() { # category, location, detail
  printf 'FAIL  [%s] %s: %s\n' "$1" "$2" "${3:0:160}" >&2
  failures=$((failures + 1))
}

# scan CATEGORY GREP-FLAG PATTERN [FILTER-FUNCTION]
# Reports every matching line in a text file that is not allowlisted and,
# when a filter function is given, for which the filter returns success.
scan() {
  local category=$1 flag=$2 pattern=$3 filter=${4:-} hit path rest lineno content
  ((${#scan_files[@]})) || return 0
  while IFS= read -r hit; do
    path=${hit%%:*}
    rest=${hit#*:}
    lineno=${rest%%:*}
    content=${rest#*:}
    allowed "$path" "$content" && continue
    if [[ -n $filter ]] && ! "$filter" "$content"; then
      continue
    fi
    report "$category" "$path:$lineno" "$content"
  done < <(printf '%s\0' "${scan_files[@]}" | xargs -0 grep -nIH "$flag" -- "$pattern" 2>/dev/null || true)
}

# --- 1. internal hostnames ---------------------------------------------------
scan internal-host -iE '\b[a-z0-9-]+\.int\.[a-z0-9-]+\.[a-z]{2,}\b|\b[a-z0-9-]+\.(internal|local|lan|corp|home\.arpa)\b'

# Maintainer-specific names (home domains, host names, vault ids, other
# projects' names) can't be listed here without publishing them. They come
# from the HYGIENE_PRIVATE_PATTERNS environment variable (a GitHub Actions
# secret in CI) or, locally, from a file outside the repository: one
# case-insensitive ERE per line, '#' comments allowed.
private_file=${HYGIENE_PRIVATE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-jetson/hygiene-private.txt}
private_patterns=${HYGIENE_PRIVATE_PATTERNS:-}
if [[ -z $private_patterns && -r $private_file ]]; then
  private_patterns=$(<"$private_file")
fi
private_re=$(grep -vE '^[[:space:]]*(#|$)' <<<"$private_patterns" | paste -sd'|' || true)
if [[ -n $private_re ]]; then
  scan private-name -iE "$private_re"
else
  echo "note: no private patterns configured; skipping the maintainer-specific scan" >&2
fi

# --- 2. RFC 1918 addresses ---------------------------------------------------
# Loopback and documentation ranges (192.0.2/24, 198.51.100/24, 203.0.113/24)
# are fine; anything else private must be allowlisted explicitly.
scan private-ipv4 -P '(?<![0-9.])(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})(?![0-9]|\.[0-9])'

# --- 3. e-mail addresses -----------------------------------------------------
email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
personal_email() { # succeed when the line has an address that is not allowed
  local addr
  while IFS= read -r addr; do
    case ${addr,,} in
      noreply@* | *@noreply.* | *@users.noreply.github.com) ;;
      *@example.com | *@example.org | *@example.net) ;;
      owner@* | *@owner.*) ;;            # OWNER placeholder
      git@github.com | git@gitlab.com) ;; # SSH remotes, not people
      *.service | *.socket | *.timer | *.target | *.path | *.mount | *.slice | *.scope | *.device) ;;
      *) return 0 ;;
    esac
  done < <(grep -oE "$email_re" <<<"$1")
  return 1
}
scan email -E "$email_re" personal_email

# --- 4. 1Password secret references ------------------------------------------
scan 1password -E 'op://'

# --- 6. vendored binaries and large blobs ------------------------------------
for f in "${files[@]}"; do
  case ${f,,} in
    *.deb | *.rpm | *.pkg.tar | *.pkg.tar.* | *.so | *.so.* | *.ko | *.ko.* | *.bin | *.img | *.iso | *.dtb | *.tbz2 | *.whl | *.jar | *.apk | *.gguf | *.safetensors)
      allowed "$f" "$f" || report binary "$f" 'binary package or blob; download it at build time with a checksum instead'
      continue
      ;;
  esac
  size=$(stat -c %s -- "$f")
  if ((size > max_bytes)) && [[ $f != assets/* ]] && ! allowed "$f" "$f"; then
    report large-file "$f" "$size bytes exceeds $max_bytes outside assets/"
  fi
done

# --- summary -----------------------------------------------------------------
if ((failures > 0)); then
  printf 'Public hygiene failed with %d finding(s) across %d files scanned.\n' "$failures" "${#files[@]}" >&2
  printf 'Fix them, or add a reviewed path:regex line to %s.\n' "$allow_file" >&2
  exit 1
fi
printf 'PASS  public hygiene (%d files scanned)\n' "${#files[@]}"
