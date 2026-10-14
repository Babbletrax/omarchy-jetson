#!/usr/bin/env bash
set -euo pipefail

failures=0
roots=("$@")
if ((${#roots[@]} == 0)); then
  roots=(config packages scripts)
fi

if rg -n --glob '*.sh' --glob 'PKGBUILD' \
  '(^|[^[:alnum:]_])(apt(-get)?|dpkg)([^[:alnum:]_]|$)' "${roots[@]}"; then
  printf 'FAIL  Debian package-management command found in host source\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS  host source uses no APT or dpkg commands\n'
fi

mapfile -t container_files < <(
  find "${roots[@]}" -type f \
    \( -name 'Dockerfile*' -o -name 'compose*.yml' -o -name 'compose*.yaml' \
       -o -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \) \
    -print | sort
)

if ((${#container_files[@]} > 0)) &&
   rg -ni '(^[[:space:]]*FROM[[:space:]]+ubuntu|image:[[:space:]]*ubuntu([:/@]|$))' \
     "${container_files[@]}"; then
  printf 'FAIL  Ubuntu container dependency found\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS  no Ubuntu container dependency\n'
fi

compose_pin_failures=0
for file in "${container_files[@]}"; do
  case "${file##*/}" in
    *compose*.yml|*compose*.yaml)
      if rg -n '^[[:space:]]*image:[[:space:]]*[^#[:space:]]+' "$file" |
         rg -v '@sha256:[0-9a-f]{64}([[:space:]]*(#.*)?)?$'; then
        compose_pin_failures=$((compose_pin_failures + 1))
      fi
      ;;
  esac
done

if ((compose_pin_failures == 0)); then
  printf 'PASS  committed Compose images are digest-pinned\n'
else
  printf 'FAIL  %d Compose file(s) contain an unpinned image\n' \
    "$compose_pin_failures" >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  printf 'Dependency policy validation failed with %d issue(s).\n' "$failures" >&2
  exit 1
fi

printf 'Dependency policy validation passed.\n'
