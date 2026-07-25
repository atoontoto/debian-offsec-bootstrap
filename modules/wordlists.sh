#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() { [[ "$OFFSEC_INSTALL_WORDLISTS" == true ]] && install_wordlists || record_skip 'wordlists'; }
