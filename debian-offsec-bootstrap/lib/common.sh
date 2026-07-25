#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_NAME=debian-offsec-bootstrap
DRY_RUN=${DRY_RUN:-false}
NON_INTERACTIVE=${NON_INTERACTIVE:-false}
FORCE_UNSUPPORTED=${FORCE_UNSUPPORTED:-false}
TMP_DIRS=()

cleanup_common() {
  local path
  for path in "${TMP_DIRS[@]:-}"; do
    [[ -n "$path" && "$path" == "${TMPDIR:-/tmp}"/* && -d "$path" ]] && rm -rf -- "$path"
  done
  return 0
}

new_temp_dir() {
  local output_name="$1" dir
  [[ "$output_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Unsafe temp variable name: $output_name"
  dir=$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_NAME}.XXXXXX")
  TMP_DIRS+=("$dir")
  printf -v "$output_name" '%s' "$dir"
}

quote_cmd() { printf '%q ' "$@"; printf '\n'; }
run() {
  if [[ "$DRY_RUN" == true ]]; then printf '[DRY-RUN] '; quote_cmd "$@"; return 0; fi
  "$@"
}

run_as_user() {
  local user="$1"; shift
  [[ "$user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "Unsafe user name: $user"
  if [[ $(id -u) -eq 0 && "$user" != root ]]; then run sudo -H -u "$user" -- "$@"; else run "$@"; fi
}

require_root() { [[ $(id -u) -eq 0 ]] || die 'Run this command as root (use sudo).'; }

invoking_user() {
  local user=${SUDO_USER:-}
  if [[ -z "$user" || "$user" == root ]]; then user=$(logname 2>/dev/null || true); fi
  [[ -n "$user" ]] || user=root
  getent passwd "$user" >/dev/null 2>&1 || die "Cannot resolve invoking user: $user"
  printf '%s\n' "$user"
}

user_home() { getent passwd "$1" | awk -F: '{print $6}'; }

validate_absolute_path() {
  local path="$1"
  [[ "$path" == /* && "$path" != / && "$path" != /home && "$path" != /opt && "$path" != /usr && "$path" != /var ]] || return 1
  [[ "$path" != *'/../'* && "$path" != */.. && "$path" != *$'\n'* ]] || return 1
}

safe_remove_tree() {
  local path="$1" allowed_root="$2" resolved root_resolved
  validate_absolute_path "$path" || die "Refusing unsafe removal path: $path"
  resolved=$(realpath -m -- "$path"); root_resolved=$(realpath -m -- "$allowed_root")
  [[ "$resolved" == "$root_resolved"/* ]] || die "Removal target is outside $allowed_root: $resolved"
  run rm -rf --one-file-system -- "$resolved"
}

atomic_install_file() {
  local source="$1" target="$2" mode="${3:-0644}" parent tmp
  parent=$(dirname -- "$target"); run install -d -m 0755 -- "$parent"
  tmp="${target}.tmp.$$"
  run install -m "$mode" -- "$source" "$tmp"
  run mv -f -- "$tmp" "$target"
}

backup_file() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  run cp -a -- "$path" "${path}.offsec-backup.$(date -u +%Y%m%dT%H%M%SZ)"
}

acquire_lock() {
  local lock="$1"
  run install -d -m 0755 -- "$(dirname -- "$lock")"
  if [[ "$DRY_RUN" == true ]]; then return 0; fi
  exec 9>"$lock"
  flock -n 9 || die "Another $PROJECT_NAME process is running."
}

is_https_url() { [[ "$1" =~ ^https://[^[:space:]]+$ ]]; }
download_https() {
  local url="$1" dest="$2"
  is_https_url "$url" || die "Refusing non-HTTPS URL: $url"
  run curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 15 --output "$dest" -- "$url"
}

verify_sha256() {
  local file="$1" expected="${2,,}" actual
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 2
  actual=$(sha256sum -- "$file" | awk '{print $1}')
  [[ "$actual" == "$expected" ]]
}

archive_is_safe() {
  local archive="$1" item
  case "$archive" in
    *.zip) while IFS= read -r item; do [[ "$item" != /* && "$item" != ../* && "$item" != *'/../'* ]] || return 1; done < <(unzip -Z1 "$archive") ;;
    *.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2) while IFS= read -r item; do [[ "$item" != /* && "$item" != ../* && "$item" != *'/../'* ]] || return 1; done < <(tar -tf "$archive") ;;
    *) return 1 ;;
  esac
}

extract_archive() {
  local archive="$1" destination="$2"
  archive_is_safe "$archive" || die "Unsafe archive paths detected: $archive"
  run install -d -m 0755 -- "$destination"
  case "$archive" in *.zip) run unzip -q "$archive" -d "$destination" ;; *) run tar -xf "$archive" -C "$destination" ;; esac
}

confirm() {
  local prompt="$1"
  [[ "$NON_INTERACTIVE" == true ]] && return 0
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

bool_value() { [[ "$1" == true || "$1" == false ]] || die "Expected true or false, got: $1"; }

classify_version() {
  local before="$1" after="$2" constraint="${3:-}"
  if [[ -n "$constraint" && "$after" != "$constraint" ]]; then printf 'held\n'
  elif [[ "$before" == "$after" ]]; then printf 'unchanged\n'
  else printf 'updated\n'; fi
}
