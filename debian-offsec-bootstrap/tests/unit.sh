#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/tests/testlib.sh"
source "$ROOT/lib/logging.sh"; source "$ROOT/lib/common.sh"; source "$ROOT/lib/platform.sh"; source "$ROOT/lib/catalog.sh"
PROJECT_ROOT="$ROOT"; OFFSEC_PROFILE=standard; SELECTED_CATEGORIES=
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT

cat > "$tmp/os-release" <<'EOF'
ID=debian
VERSION_ID="13"
VERSION_CODENAME=trixie
EOF
OFFSEC_OS_RELEASE_FILE="$tmp/os-release" OFFSEC_TEST_ARCH=amd64 detect_platform
assert 'OS detection identifies Debian 13' test "$DETECTED_ID:$DETECTED_VERSION:$DETECTED_ARCH" = debian:13:amd64
source "$ROOT/config/load.sh"; OFFSEC_PROFILE=core; load_offsec_config "$ROOT"
assert 'environment overrides configuration defaults' test "$OFFSEC_PROFILE" = core
OFFSEC_PROFILE=standard
assert 'argument parser exposes help' bash "$ROOT/install.sh" --help
if bash "$ROOT/install.sh" --definitely-invalid >/dev/null 2>&1; then fail 'invalid argument is rejected'; else pass 'invalid argument is rejected'; fi
assert 'manifest parser accepts catalog' catalog_validate "$ROOT/manifests/tool-catalog.tsv"

DRY_RUN=true; run touch "$tmp/dry-run-file" >/dev/null
if [[ ! -e "$tmp/dry-run-file" ]]; then pass 'dry-run performs no mutation'; else fail 'dry-run performs no mutation'; fi
DRY_RUN=false
assert 'safe child path accepted' validate_absolute_path /opt/offsec/tools/demo
if validate_absolute_path /opt/../etc; then fail 'traversal path rejected'; else pass 'traversal path rejected'; fi
printf 'checksum fixture' > "$tmp/checksum"
digest=$(sha256sum "$tmp/checksum" | awk '{print $1}')
assert 'SHA-256 verification succeeds' verify_sha256 "$tmp/checksum" "$digest"
if verify_sha256 "$tmp/checksum" "${digest%?}0"; then fail 'bad checksum rejected'; else pass 'bad checksum rejected'; fi

python_cmd=python
python3 -c 'import sys' >/dev/null 2>&1 && python_cmd=python3
"$python_cmd" - "$tmp/evil.zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z: z.writestr('../escape', 'bad')
PY
if archive_is_safe "$tmp/evil.zip"; then fail 'archive traversal rejected'; else pass 'archive traversal rejected'; fi
assert 'update classification updated' test "$(classify_version 1 2)" = updated
assert 'update classification unchanged' test "$(classify_version 2 2)" = unchanged
assert 'update classification held' test "$(classify_version 1 2 1)" = held
redacted=$(printf 'password=hunter2 token=abc123\n' | redact)
if [[ "$redacted" != *hunter2* && "$redacted" != *abc123* ]]; then pass 'secret redaction'; else fail 'secret redaction'; fi
grep -Fq 'sudo -H -u "$user"' "$ROOT/lib/common.sh" && pass 'root-to-user transition uses sudo -H -u' || fail 'root-to-user transition uses sudo -H -u'
grep -Fq 'apt_package_exists' "$ROOT/lib/apt.sh" && pass 'invalid packages are classified before install' || fail 'invalid packages are classified before install'

"$python_cmd" "$ROOT/scripts/build-inventory.py" --catalog "$ROOT/manifests/tool-catalog.tsv" --profile core --output "$tmp/inventory.json" --owner tester
"$python_cmd" - "$tmp/inventory.json" <<'PY' && pass 'inventory generation emits valid schema' || fail 'inventory generation emits valid schema'
import json, sys
d=json.load(open(sys.argv[1], encoding='utf-8'))
assert d['schema_version']==1 and d['profile']=='core' and len(d['tools'])==25
PY
finish
