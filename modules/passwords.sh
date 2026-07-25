#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
module_install() { install_category_channels passwords; }
