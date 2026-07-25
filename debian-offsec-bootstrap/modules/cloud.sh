#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() { [[ "$OFFSEC_INSTALL_CLOUD" == true ]] && install_category_channels cloud; }
