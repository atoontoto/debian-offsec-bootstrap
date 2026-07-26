#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() {
  install_category_channels web
  if [[ "$OFFSEC_INSTALL_BURP" == true ]]; then install_burp; fi
  return 0
}
