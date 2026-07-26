#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

detect_platform() {
  local os_release=${OFFSEC_OS_RELEASE_FILE:-/etc/os-release}
  [[ -r "$os_release" ]] || die "$os_release is missing."
  # shellcheck disable=SC1091
  # The path is either /etc/os-release or a unit-test fixture.
  # shellcheck disable=SC1090
  source "$os_release"
  DETECTED_ID=${ID:-unknown}
  DETECTED_VERSION=${VERSION_ID:-unknown}
  DETECTED_CODENAME=${VERSION_CODENAME:-unknown}
  DETECTED_ARCH=${OFFSEC_TEST_ARCH:-$(dpkg --print-architecture 2>/dev/null || uname -m)}
  export DETECTED_ID DETECTED_VERSION DETECTED_CODENAME DETECTED_ARCH
}

validate_platform() {
  detect_platform
  if [[ "$DETECTED_ID" != debian || "$DETECTED_VERSION" != 13 || "$DETECTED_ARCH" != amd64 ]]; then
    [[ "$FORCE_UNSUPPORTED" == true ]] || die "Supported platform is Debian 13 amd64; detected $DETECTED_ID $DETECTED_VERSION $DETECTED_ARCH."
    log_warn "Continuing on unsupported $DETECTED_ID $DETECTED_VERSION $DETECTED_ARCH."
  fi
}

nearest_existing_parent() {
  local path="$1" parent
  [[ "$path" == /* ]] || return 1
  while [[ "$path" != / && "$path" == */ ]]; do path=${path%/}; done
  while [[ ! -e "$path" ]]; do
    [[ -L "$path" ]] && return 1
    parent=$(dirname -- "$path") || return 1
    [[ "$parent" != "$path" ]] || return 1
    path="$parent"
  done
  [[ -d "$path" ]] || return 1
  realpath -e -- "$path"
}

disk_available_kib() {
  local path="$1" output available
  output=$(LC_ALL=C df -Pk -- "$path" 2>/dev/null) || return 1
  available=$(awk 'NR == 2 && $4 ~ /^[0-9]+$/ { print $4; found=1 } END { if (!found) exit 1 }' <<< "$output") || return 1
  [[ "$available" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$available"
}

filesystem_id() { stat -Lc '%d' -- "$1"; }

format_kib_gib() { awk -v kib="$1" 'BEGIN { printf "%.2f", kib / 1048576 }'; }

free_gib() {
  local probe available
  probe=$(nearest_existing_parent "${OFFSEC_INSTALL_ROOT:-/opt/offsec}") || return 1
  available=$(disk_available_kib "$probe") || return 1
  format_kib_gib "$available"
}

check_disk_space() {
  local entry label path probe fs_id available display required_kib
  local destinations=(
    "installation root|$OFFSEC_INSTALL_ROOT"
    "wordlist root|$OFFSEC_WORDLIST_ROOT"
    "state root|$OFFSEC_STATE_ROOT"
    "log root|$OFFSEC_LOG_ROOT"
  )
  declare -A checked=()
  required_kib=$((OFFSEC_MIN_FREE_GIB * 1024 * 1024))
  for entry in "${destinations[@]}"; do
    label=${entry%%|*}; path=${entry#*|}
    probe=$(nearest_existing_parent "$path") || die "Cannot locate an existing parent filesystem for $label: $path"
    fs_id=$(filesystem_id "$probe") || die "Cannot identify the filesystem for $label: $path"
    [[ -z ${checked[$fs_id]:-} ]] || continue
    checked[$fs_id]=1
    available=$(disk_available_kib "$probe") || die "Cannot determine free space for $label ($path; checked $probe)."
    display=$(format_kib_gib "$available")
    ((available >= required_kib)) || die "Only ${display} GiB free for $label ($path); at least ${OFFSEC_MIN_FREE_GIB} GiB is required."
    log_info "Disk space for $label ($path): ${display} GiB available (checked $probe)."
  done
}

network_available() {
  curl -fsSIL --connect-timeout 5 https://deb.debian.org/ >/dev/null 2>&1 || \
    curl -fsSIL --connect-timeout 5 https://github.com/ >/dev/null 2>&1
}
