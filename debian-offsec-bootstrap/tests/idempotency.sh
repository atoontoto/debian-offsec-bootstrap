#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
HOME="$tmp" bash "$ROOT/scripts/offsec-project-new" demo >/dev/null
HOME="$tmp" bash "$ROOT/scripts/offsec-project-new" demo >/dev/null
expected='evidence loot notes reports scans screenshots scripts'
actual=$(find "$tmp/engagements/demo" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | xargs)
[[ "$actual" == "$expected" ]]
printf 'Idempotency test passed.\n'
