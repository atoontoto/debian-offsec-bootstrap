#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() { install_category_channels ad; [[ "$OFFSEC_INSTALL_BLOODHOUND" == true ]] && install_bloodhound_stack; }
