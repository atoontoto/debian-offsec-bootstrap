#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

declare -ag OFFSEC_SUCCEEDED=() OFFSEC_FAILED_OPTIONAL=() OFFSEC_FAILED_REQUIRED=() OFFSEC_SKIPPED=()
OFFSEC_COLOR=false
OFFSEC_LOGGING_STARTED=false
OFFSEC_LOG_PID=
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
  sed -uE 's/((token|password|secret|authorization|api[_-]?key)[=:][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig'
}

record_success() {
  if [[ ${DRY_RUN:-false} == true ]]; then log_info "[DRY-RUN] would complete: $1"; return 0; fi
  OFFSEC_SUCCEEDED+=("$1"); log_ok "$1"
}
record_skip() { OFFSEC_SKIPPED+=("$1"); log_warn "Skipped: $1"; }
record_failure() {
  local item="$1" required="${2:-false}"
  if [[ "$required" == true ]]; then OFFSEC_FAILED_REQUIRED+=("$item"); else OFFSEC_FAILED_OPTIONAL+=("$item"); fi
  log_error "$item"
}

print_result_summary() {
  printf '\nSummary: %d succeeded, %d optional failures, %d required failures, %d skipped\n' \
    "${#OFFSEC_SUCCEEDED[@]}" "${#OFFSEC_FAILED_OPTIONAL[@]}" "${#OFFSEC_FAILED_REQUIRED[@]}" "${#OFFSEC_SKIPPED[@]}"
  if ((${#OFFSEC_FAILED_OPTIONAL[@]})); then printf 'Optional failures: %s\n' "$(IFS=', '; echo "${OFFSEC_FAILED_OPTIONAL[*]}")"; fi
  if ((${#OFFSEC_FAILED_REQUIRED[@]})); then printf 'Required failures: %s\n' "$(IFS=', '; echo "${OFFSEC_FAILED_REQUIRED[*]}")"; fi
  return 0
}

start_logging() {
  local log_file="$1" structured_file="$2" event="$3"
  if [[ "$OFFSEC_LOGGING_STARTED" == true ]]; then log_warn 'Logging is already active; duplicate initialization was ignored.'; return 0; fi
  for file in "$log_file" "$structured_file"; do
    [[ ! -L "$file" && ( ! -e "$file" || -f "$file" ) ]] || die "Unsafe log file: $file"
  done
  OFFSEC_COLOR=false
  touch "$log_file" "$structured_file"
  chmod 0640 "$log_file" "$structured_file"
  printf '{"timestamp":"%s","event":"%s","pid":%d}\n' "$(date -u +%FT%TZ)" "$event" "$$" >> "$structured_file"
  exec 3>&1 4>&2
  exec > >(redact | tee -a "$log_file") 2>&1
  OFFSEC_LOG_PID=$!
  OFFSEC_LOGGING_STARTED=true
}

stop_logging() {
  local status=0
  [[ "$OFFSEC_LOGGING_STARTED" == true ]] || return 0
  exec 1>&3 2>&4 3>&- 4>&-
  if [[ -n "$OFFSEC_LOG_PID" ]]; then wait "$OFFSEC_LOG_PID" || status=$?; fi
  OFFSEC_LOGGING_STARTED=false
  OFFSEC_LOG_PID=
  return "$status"
}
