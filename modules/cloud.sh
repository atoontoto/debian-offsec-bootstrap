#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() {
  if [[ "$OFFSEC_INSTALL_CLOUD" == true ]]; then install_category_channels cloud; else record_skip 'cloud category (disabled)'; fi
  return 0
}
