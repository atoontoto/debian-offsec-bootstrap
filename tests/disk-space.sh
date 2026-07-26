#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/tests/testlib.sh"
source "$ROOT/lib/logging.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/platform.sh"
PROJECT_ROOT="$ROOT"
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/existing parent"

expected=$(realpath -e "$tmp/existing parent")
assert 'existing destination selects itself' test "$(nearest_existing_parent "$tmp/existing parent")" = "$expected"
assert 'missing destination selects nearest parent' test "$(nearest_existing_parent "$tmp/existing parent/one/two")" = "$expected"
assert 'trailing slash is normalized' test "$(nearest_existing_parent "$tmp/existing parent/one/two/")" = "$expected"
if [[ $(uname -s) == MINGW* ]]; then
  printf '# SKIP: POSIX symlink disk tests are unavailable under Git for Windows.\n'
else
  ln -s "$tmp/existing parent" "$tmp/parent-link"
  assert 'symlink parent resolves to its backing directory' test "$(nearest_existing_parent "$tmp/parent-link/missing")" = "$expected"
  ln -s "$tmp/absent-target" "$tmp/broken-link"
  if nearest_existing_parent "$tmp/broken-link" >/dev/null; then fail 'broken destination symlink is rejected'; else pass 'broken destination symlink is rejected'; fi
fi

df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/mock 9000000 1 7340032 1%% /\n'; }
assert 'valid df output returns KiB without GiB truncation' test "$(disk_available_kib /)" = 7340032
df() { printf 'unexpected output\n'; }
if disk_available_kib / >/dev/null; then fail 'invalid df output is unknown, not zero'; else pass 'invalid df output is unknown, not zero'; fi
df() { return 9; }
if disk_available_kib / >/dev/null; then fail 'df failure is unknown, not zero'; else pass 'df failure is unknown, not zero'; fi
unset -f df

OFFSEC_INSTALL_ROOT="$tmp/existing parent/missing/install"
available=$(free_gib)
awk -v value="$available" 'BEGIN { exit !(value > 0) }' && pass 'missing installation root does not fabricate zero GiB' || fail 'missing installation root does not fabricate zero GiB'

if (
  OFFSEC_MIN_FREE_GIB=2
  OFFSEC_INSTALL_ROOT=/mock/install; OFFSEC_WORDLIST_ROOT=/mock/wordlists; OFFSEC_STATE_ROOT=/mock/state; OFFSEC_LOG_ROOT=/mock/log
  nearest_existing_parent() { printf '%s\n' "$1"; }
  filesystem_id() { printf 'same\n'; }
  disk_available_kib() { printf '1048575\n'; }
  check_disk_space
) >/dev/null 2>&1; then fail 'nearly full filesystem is rejected'; else pass 'nearly full filesystem is rejected'; fi

calls="$tmp/df-calls"
(
  OFFSEC_MIN_FREE_GIB=1
  OFFSEC_INSTALL_ROOT=/mock/install; OFFSEC_WORDLIST_ROOT=/mock/wordlists; OFFSEC_STATE_ROOT=/mock/state; OFFSEC_LOG_ROOT=/mock/log
  nearest_existing_parent() { printf '%s\n' "$1"; }
  filesystem_id() { printf '%s\n' "$1"; }
  disk_available_kib() { printf '%s\n' "$1" >> "$calls"; printf '2097152\n'; }
  check_disk_space >/dev/null
)
assert 'all distinct destination filesystems are checked' test "$(wc -l < "$calls" | tr -d ' ')" = 4
finish
