#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() {
  [[ "$OFFSEC_INSTALL_WIRELESS" == true ]] || { record_skip 'wireless category (enable explicitly)'; return; }
  log_warn 'Wireless hardware is required; monitor mode and NetworkManager are not changed.'
  install_category_channels wireless
}
