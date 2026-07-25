#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() { desktop_install "$OFFSEC_DESKTOP"; install_shell_integration; }
