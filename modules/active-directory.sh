#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() {
  install_category_channels ad
  if [[ "$OFFSEC_INSTALL_BLOODHOUND" == true ]]; then install_bloodhound_stack; fi
  return 0
}
