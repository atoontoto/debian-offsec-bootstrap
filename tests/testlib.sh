#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
TESTS=0 FAILURES=0
pass() { TESTS=$((TESTS+1)); printf 'ok %d - %s\n' "$TESTS" "$1"; }
fail() { TESTS=$((TESTS+1)); FAILURES=$((FAILURES+1)); printf 'not ok %d - %s\n' "$TESTS" "$1" >&2; }
assert() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
finish() { printf '1..%d\n' "$TESTS"; ((FAILURES == 0)); }
