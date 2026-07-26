#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APT_UPDATED=false

apt_refresh() {
  local audit
  [[ "$APT_UPDATED" == true ]] && return 0
  audit=$(dpkg --audit 2>/dev/null) || die 'dpkg audit failed; repair package state before continuing.'
  if [[ -n "$audit" ]]; then
    log_warn 'Interrupted or incomplete dpkg state detected; running dpkg --configure -a.'
    run env DEBIAN_FRONTEND=noninteractive dpkg --configure -a
  fi
  run env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 update
  APT_UPDATED=true
}

apt_package_exists() { apt-cache show --no-all-versions -- "$1" >/dev/null 2>&1; }

apt_install_packages() {
  local required="${1:-false}"; shift
  local package available=() unavailable=()
  apt_refresh
  for package in "$@"; do
    if apt_package_exists "$package"; then available+=("$package"); else unavailable+=("$package"); fi
  done
  if ((${#available[@]})); then
    if run env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends -- "${available[@]}"; then
      for package in "${available[@]}"; do record_success "apt:$package"; done
    else
      for package in "${available[@]}"; do record_failure "apt:$package" "$required"; done
    fi
  fi
  for package in "${unavailable[@]}"; do record_failure "apt:$package (unavailable in configured repositories)" "$required"; done
}

apt_install_foundation() {
  local packages=() line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%%#*}; line=${line//[[:space:]]/}
    [[ -n "$line" ]] && packages+=("$line")
  done < "$PROJECT_ROOT/manifests/apt-packages.txt"
  apt_install_packages true "${packages[@]}"
}

apt_install_category() {
  local category="$1" row package profile
  local required_packages=() optional_packages=()
  while IFS= read -r row; do
    IFS=$'\t' read -r _ _ _ _ package _ _ _ _ _ _ _ _ _ _ profile _ <<< "$row"
    if [[ "$profile" == core ]]; then required_packages+=("$package"); else optional_packages+=("$package"); fi
  done < <(catalog_rows apt "$category")
  if ((${#required_packages[@]})); then apt_install_packages true "${required_packages[@]}"; fi
  if ((${#optional_packages[@]})); then apt_install_packages false "${optional_packages[@]}"; fi
  return 0
}

apt_safe_upgrade() {
  apt_refresh
  if [[ "$OFFSEC_SAFE_UPGRADE" == true ]]; then run env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 upgrade -y --with-new-pkgs; fi
  return 0
}
