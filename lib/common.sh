#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_NAME=debian-offsec-bootstrap
DRY_RUN=${DRY_RUN:-false}
NON_INTERACTIVE=${NON_INTERACTIVE:-false}
FORCE_UNSUPPORTED=${FORCE_UNSUPPORTED:-false}
TMP_DIRS=()
TMP_FILES=()
MANAGED_STAGE_DIRS=()

cleanup_common() {
  local path
  for path in "${TMP_DIRS[@]:-}"; do
    [[ -n "$path" && "$path" == "${TMPDIR:-/tmp}"/* && -d "$path" ]] && rm -rf -- "$path"
  done
  for path in "${TMP_FILES[@]:-}"; do
    [[ -n "$path" && -f "$path" ]] && rm -f -- "$path"
  done
  for path in "${MANAGED_STAGE_DIRS[@]:-}"; do
    if [[ -n "$path" && -n ${OFFSEC_INSTALL_ROOT:-} && "$path" == "$OFFSEC_INSTALL_ROOT"/.bootstrap-stage.* && -d "$path" ]]; then rm -rf --one-file-system -- "$path"; fi
  done
  if declare -F stop_logging >/dev/null 2>&1; then stop_logging || printf '[FAIL] Logging pipeline did not shut down cleanly.\n' >&2; fi
  return 0
}

new_temp_dir() {
  local output_name="$1" dir
  [[ "$output_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Unsafe temp variable name: $output_name"
  dir=$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_NAME}.XXXXXX")
  TMP_DIRS+=("$dir")
  printf -v "$output_name" '%s' "$dir"
}

new_bootstrap_stage_dir() {
  local output_name="$1" dir
  [[ "$output_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Unsafe stage variable name: $output_name"
  dir=$(mktemp -d "$OFFSEC_INSTALL_ROOT/.bootstrap-stage.XXXXXX")
  MANAGED_STAGE_DIRS+=("$dir")
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

report_entrypoint_error() {
  local status="$1" line="$2" entrypoint="$3"
  log_error "$entrypoint failed at line $line (exit $status)."
  return "$status"
}

invoking_user() {
  local user current_uid
  current_uid=$(id -u)
  if [[ -n ${SUDO_USER:-} && "$SUDO_USER" != root ]]; then
    user="$SUDO_USER"
  elif [[ "$current_uid" == 0 ]]; then
    user=root
  else
    user=$(id -un)
  fi
  [[ "$user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die "Unsafe invoking user name: $user"
  getent passwd "$user" >/dev/null 2>&1 || die "Cannot resolve invoking user: $user"
  if [[ -n ${SUDO_UID:-} ]]; then
    [[ "$SUDO_UID" =~ ^[0-9]+$ && $(id -u "$user") == "$SUDO_UID" ]] || die "SUDO_UID does not match SUDO_USER: $user"
  fi
  if [[ -n ${SUDO_GID:-} ]]; then
    [[ "$SUDO_GID" =~ ^[0-9]+$ && $(id -g "$user") == "$SUDO_GID" ]] || die "SUDO_GID does not match SUDO_USER: $user"
  fi
  printf '%s\n' "$user"
}

user_home() { getent passwd "$1" | awk -F: '{print $6}'; }

validate_absolute_path() {
  local path="$1" resolved
  [[ "$path" == /* && "$path" != / && "$path" != /home && "$path" != /opt && "$path" != /usr && "$path" != /var ]] || return 1
  [[ "$path" != *'/../'* && "$path" != */.. && "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]] || return 1
  [[ "$path" != *'*'* && "$path" != *'?'* && "$path" != *'['* && "$path" != *']'* ]] || return 1
  resolved=$(realpath -m -- "$path") || return 1
  [[ "$resolved" != / && "$resolved" != /home && "$resolved" != /opt && "$resolved" != /usr && "$resolved" != /var && "$resolved" != /var/lib && "$resolved" != /var/log && "$resolved" != /usr/share && "$resolved" != /usr/local ]] || return 1
}

validate_managed_root() {
  local path="$1"
  validate_absolute_path "$path" || return 1
  [[ ! -L "$path" || -e "$path" ]] || return 1
  [[ ! -e "$path" || -d "$path" ]] || return 1
}

validate_runtime_config() {
  local value path
  for value in "$DRY_RUN" "$NON_INTERACTIVE" "$FORCE_UNSUPPORTED" "$OFFSEC_INSTALL_BURP" "$OFFSEC_INSTALL_BLOODHOUND" \
    "$OFFSEC_INSTALL_WORDLISTS" "$OFFSEC_INSTALL_WIRELESS" "$OFFSEC_INSTALL_CLOUD" "$OFFSEC_ALLOW_DOCKER_GROUP" \
    "$OFFSEC_AUTO_START_SERVICES" "$OFFSEC_SAFE_UPGRADE" "$OFFSEC_WIRESHARK_CAPTURE_GROUP"; do
    bool_value "$value"
  done
  [[ "$OFFSEC_UPDATE_CHANNEL" =~ ^(stable|latest)$ ]] || die "Invalid update channel: $OFFSEC_UPDATE_CHANNEL"
  [[ "$OFFSEC_MIN_FREE_GIB" =~ ^[0-9]+$ ]] && ((OFFSEC_MIN_FREE_GIB > 0)) || die "OFFSEC_MIN_FREE_GIB must be a positive integer."
  for path in "$OFFSEC_INSTALL_ROOT" "$OFFSEC_WORDLIST_ROOT" "$OFFSEC_LOG_ROOT" "$OFFSEC_STATE_ROOT"; do
    validate_managed_root "$path" || die "Unsafe managed directory: $path"
  done
}

valid_category() {
  [[ "$1" =~ ^(base|network|web|ad|passwords|exploitation|cloud|wireless|reverse-engineering|forensics|osint|containers|wordlists|desktop)$ ]]
}

path_is_within() {
  local child="$1" root="$2"
  if [[ "$root" == / ]]; then [[ "$child" == /* && "$child" != / ]]; else [[ "$child" == "$root"/* ]]; fi
}

safe_remove_tree() {
  local path="$1" allowed_root="$2" resolved root_resolved
  validate_absolute_path "$path" || die "Refusing unsafe removal path: $path"
  resolved=$(realpath -m -- "$path"); root_resolved=$(realpath -m -- "$allowed_root")
  path_is_within "$resolved" "$root_resolved" || die "Removal target is outside $allowed_root: $resolved"
  run rm -rf --one-file-system -- "$resolved"
}

ensure_managed_directory() {
  local path="$1" allowed_root="$2" mode="${3:-0755}" resolved root_resolved
  resolved=$(realpath -m -- "$path") || die "Cannot resolve managed directory: $path"
  root_resolved=$(realpath -m -- "$allowed_root") || die "Cannot resolve managed root: $allowed_root"
  path_is_within "$resolved" "$root_resolved" || die "Managed directory is outside $allowed_root: $resolved"
  [[ ! -L "$path" && ( ! -e "$path" || -d "$path" ) ]] || die "Unsafe managed directory: $path"
  run install -d -m "$mode" -- "$path"
}

remove_managed_symlink() {
  local link="$1" allowed_root="$2" resolved root_resolved
  [[ -L "$link" ]] || return 0
  resolved=$(realpath -m -- "$link") || die "Cannot resolve managed link: $link"
  root_resolved=$(realpath -m -- "$allowed_root") || die "Cannot resolve managed root: $allowed_root"
  path_is_within "$resolved" "$root_resolved" || die "Refusing to remove link outside $allowed_root: $link -> $resolved"
  run rm -f -- "$link"
}

install_managed_symlink() {
  local target="$1" link="$2" allowed_root="$3" target_resolved link_resolved root_resolved
  target_resolved=$(realpath -m -- "$target") || die "Cannot resolve managed link target: $target"
  root_resolved=$(realpath -m -- "$allowed_root") || die "Cannot resolve managed root: $allowed_root"
  path_is_within "$target_resolved" "$root_resolved" || die "Managed link target is outside $allowed_root: $target_resolved"
  if [[ -e "$link" || -L "$link" ]]; then
    [[ -L "$link" ]] || die "Refusing to replace an unmanaged file: $link"
    link_resolved=$(realpath -m -- "$link") || die "Cannot resolve existing link: $link"
    path_is_within "$link_resolved" "$root_resolved" || die "Refusing to replace an unmanaged link: $link -> $link_resolved"
  fi
  run ln -sfn -- "$target" "$link"
}

install_project_helper_link() {
  local source="$1" target="$2" installed_source
  installed_source="$OFFSEC_INSTALL_ROOT/bootstrap/scripts/$(basename -- "$source")"
  if [[ -f "$target" && ! -L "$target" ]]; then
    if cmp -s -- "$source" "$target" || { [[ -f "$installed_source" ]] && cmp -s -- "$installed_source" "$target"; }; then
      run rm -f -- "$target"
      if [[ "$DRY_RUN" == true ]]; then run ln -sfn -- "$installed_source" "$target"; return 0; fi
    else
      die "Refusing to overwrite a modified helper: $target"
    fi
  fi
  install_managed_symlink "$installed_source" "$target" "$OFFSEC_INSTALL_ROOT"
}

atomic_install_file() {
  local source="$1" target="$2" mode="${3:-0644}" parent tmp base
  parent=$(dirname -- "$target"); run install -d -m 0755 -- "$parent"
  if [[ "$DRY_RUN" == true ]]; then
    run install -m "$mode" -- "$source" "${target}.tmp"
    run mv -f -- "${target}.tmp" "$target"
    return 0
  fi
  base=$(basename -- "$target")
  tmp=$(mktemp "$parent/.${base}.tmp.XXXXXX")
  TMP_FILES+=("$tmp")
  run install -m "$mode" -- "$source" "$tmp"
  run mv -f -- "$tmp" "$target"
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

python_runtime() {
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then printf 'python3\n'
  elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then printf 'python\n'
  else return 1
  fi
}

archive_is_safe() {
  local archive="$1" python_cmd
  case "$archive" in *.zip|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.bz2) ;; *) return 1 ;; esac
  python_cmd=$(python_runtime) || return 1
  "$python_cmd" "$PROJECT_ROOT/scripts/validate-archive.py" "$archive"
}

extract_archive() {
  local archive="$1" destination="$2"
  archive_is_safe "$archive" || die "Unsafe archive paths detected: $archive"
  [[ ! -L "$destination" ]] || die "Refusing symlink extraction destination: $destination"
  if [[ -d "$destination" ]]; then
    [[ -z $(find "$destination" -mindepth 1 -maxdepth 1 -print -quit) ]] || die "Extraction destination is not empty: $destination"
  elif [[ -e "$destination" ]]; then
    die "Extraction destination is not a directory: $destination"
  fi
  run install -d -m 0755 -- "$destination"
  case "$archive" in *.zip) run unzip -q "$archive" -d "$destination" ;; *) run tar -xf "$archive" -C "$destination" ;; esac
}

has_controlling_terminal() {
  [[ -e /dev/tty ]] || return 1
  { : </dev/tty && : >/dev/tty; } 2>/dev/null
}

prompt_read() {
  local prompt="$1" output_name="$2" reply
  [[ "$output_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Unsafe prompt variable name: $output_name"
  has_controlling_terminal || { log_error 'Interactive input requested, but no controlling terminal is available.'; return 2; }
  printf '%s' "$prompt" >/dev/tty || return 2
  if IFS= read -r reply </dev/tty; then
    printf '\n' >/dev/tty
    printf -v "$output_name" '%s' "$reply"
    return 0
  fi
  printf '\n' >/dev/tty 2>/dev/null || true
  return 1
}

confirm() {
  local prompt="$1" answer
  [[ "$NON_INTERACTIVE" == true ]] && return 1
  prompt_read "$prompt [y/N] " answer || return $?
  [[ "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

bool_value() { [[ "$1" == true || "$1" == false ]] || die "Expected true or false, got: $1"; }

classify_version() {
  local before="$1" after="$2" constraint="${3:-}"
  if [[ -n "$constraint" && "$after" != "$constraint" ]]; then printf 'held\n'
  elif [[ "$before" == "$after" ]]; then printf 'unchanged\n'
  else printf 'updated\n'; fi
}
