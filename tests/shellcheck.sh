#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
command -v shellcheck >/dev/null 2>&1 || { echo 'shellcheck is required' >&2; exit 127; }
mapfile -d '' scripts < <(find "$ROOT" -type f \( -name '*.sh' -o -path '*/scripts/offsec-*' \) -print0)
shellcheck --external-sources --severity=warning "${scripts[@]}"
