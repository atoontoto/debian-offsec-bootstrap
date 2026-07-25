#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

declare -ag OFFSEC_SUCCEEDED=() OFFSEC_FAILED_OPTIONAL=() OFFSEC_FAILED_REQUIRED=() OFFSEC_SKIPPED=()
OFFSEC_COLOR=false
[[ -t 1 && -z "${NO_COLOR:-}" ]] && OFFSEC_COLOR=true

_log_color() {
  local code="$1"; shift
  if [[ "$OFFSEC_COLOR" == true ]]; then printf '\033[%sm%s\033[0m\n' "$code" "$*"; else printf '%s\n' "$*"; fi
}

log_info() { _log_color '1;34' "[INFO] $*"; }
log_ok() { _log_color '1;32' "[ OK ] $*"; }
log_warn() { _log_color '1;33' "[WARN] $*" >&2; }
log_error() { _log_color '1;31' "[FAIL] $*" >&2; }
die() { log_error "$*"; exit 1; }

redact() {
  sed -E 's/((token|password|secret|authorization|api[_-]?key)[=:][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig'
}

record_success() { OFFSEC_SUCCEEDED+=("$1"); log_ok "$1"; }
record_skip() { OFFSEC_SKIPPED+=("$1"); log_warn "Skipped: $1"; }
record_failure() {
  local item="$1" required="${2:-false}"
  if [[ "$required" == true ]]; then OFFSEC_FAILED_REQUIRED+=("$item"); else OFFSEC_FAILED_OPTIONAL+=("$item"); fi
  log_error "$item"
}

print_result_summary() {
  printf '\nSummary: %d succeeded, %d optional failures, %d required failures, %d skipped\n' \
    "${#OFFSEC_SUCCEEDED[@]}" "${#OFFSEC_FAILED_OPTIONAL[@]}" "${#OFFSEC_FAILED_REQUIRED[@]}" "${#OFFSEC_SKIPPED[@]}"
  ((${#OFFSEC_FAILED_OPTIONAL[@]})) && printf 'Optional failures: %s\n' "$(IFS=', '; echo "${OFFSEC_FAILED_OPTIONAL[*]}")"
  ((${#OFFSEC_FAILED_REQUIRED[@]})) && printf 'Required failures: %s\n' "$(IFS=', '; echo "${OFFSEC_FAILED_REQUIRED[*]}")"
}

start_logging() {
  local log_file="$1" structured_file="$2" event="$3"
  OFFSEC_COLOR=false
  touch "$log_file" "$structured_file"
  chmod 0640 "$log_file" "$structured_file"
  printf '{"timestamp":"%s","event":"%s","pid":%d}\n' "$(date -u +%FT%TZ)" "$event" "$$" >> "$structured_file"
  exec > >(redact | tee -a "$log_file") 2>&1
}
