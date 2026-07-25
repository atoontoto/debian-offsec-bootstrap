#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
for script in install.sh update.sh verify.sh uninstall.sh; do bash "$ROOT/$script" --help >/dev/null; done
python_cmd=python
python3 -c 'import sys' >/dev/null 2>&1 && python_cmd=python3
cache=$(mktemp -d); trap 'rm -rf -- "$cache"' EXIT
PYTHONPYCACHEPREFIX="$cache" "$python_cmd" -m py_compile "$ROOT/scripts/build-inventory.py" "$ROOT/scripts/generate-catalog.py"
printf 'Smoke tests passed.\n'
