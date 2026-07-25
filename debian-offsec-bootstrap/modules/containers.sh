#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() {
  install_category_channels containers
  if [[ "$OFFSEC_ALLOW_DOCKER_GROUP" == true ]]; then
    local user; user=$(invoking_user)
    log_warn 'Docker group membership is effectively root-equivalent.'
    [[ "$user" != root ]] && run usermod -aG docker "$user"
  fi
}
