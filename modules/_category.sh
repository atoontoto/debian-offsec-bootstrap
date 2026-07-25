#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

install_category_channels() {
  local category="$1"
  log_info "Installing category: $category"
  apt_install_category "$category"
  pipx_install_category "$category"
  go_install_category "$category"
  cargo_install_category "$category"
  github_install_category "$category"
  report_manual_category "$category"
}
