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

free_gib() { df -Pk "${OFFSEC_INSTALL_ROOT:-/opt/offsec}" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024/1024}' || printf '0'; }
check_disk_space() {
  local free
  free=$(free_gib)
  ((free >= OFFSEC_MIN_FREE_GIB)) || die "Only ${free} GiB free; at least ${OFFSEC_MIN_FREE_GIB} GiB is required."
}

network_available() {
  curl -fsSIL --connect-timeout 5 https://deb.debian.org/ >/dev/null 2>&1 || \
    curl -fsSIL --connect-timeout 5 https://github.com/ >/dev/null 2>&1
}
