#!/usr/bin/env bash

set -Eeuo pipefail

readonly duration_seconds=${1:-180}
readonly output_dir=${2:-/tmp}
readonly started_at=$SECONDS

if [[ ! "$duration_seconds" =~ ^[1-9][0-9]*$ ]]; then
  printf 'duration must be a positive integer\n' >&2
  exit 2
fi

mkdir -p "$output_dir"

capture_port() {
  local port=$1
  local output="$output_dir/orin-boot-${port##*/}.log"

  : >"$output"
  while ((SECONDS - started_at < duration_seconds)); do
    if [[ -c "$port" ]]; then
      stty -F "$port" 115200 raw -echo -ixon -ixoff 2>/dev/null || true
      timeout 2s stdbuf -o0 tr -d '\000' <"$port" >>"$output" || true
    else
      sleep 0.1
    fi
  done
}

pids=()
for index in 0 1 2 3; do
  capture_port "/dev/ttyACM$index" &
  pids+=("$!")
done

for pid in "${pids[@]}"; do
  wait "$pid"
done
