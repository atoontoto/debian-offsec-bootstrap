#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

load_offsec_config() {
  local root="$1" name key local_file mode owner
  local names=(OFFSEC_PROFILE OFFSEC_DESKTOP OFFSEC_INSTALL_BURP OFFSEC_INSTALL_BLOODHOUND OFFSEC_INSTALL_WORDLISTS OFFSEC_INSTALL_WIRELESS OFFSEC_INSTALL_CLOUD OFFSEC_UPDATE_CHANNEL OFFSEC_ALLOW_DOCKER_GROUP OFFSEC_AUTO_START_SERVICES OFFSEC_INSTALL_ROOT OFFSEC_WORDLIST_ROOT OFFSEC_LOG_ROOT OFFSEC_STATE_ROOT OFFSEC_SAFE_UPGRADE OFFSEC_MIN_FREE_GIB OFFSEC_GDB_PLUGIN OFFSEC_BURP_DOWNLOAD_URL OFFSEC_BURP_SHA256 OFFSEC_METASPLOIT_INSTALLER OFFSEC_WIRESHARK_CAPTURE_GROUP)
  declare -A saved=()
  for name in "${names[@]}"; do [[ -v $name ]] && saved[$name]=${!name}; done
  # shellcheck source=defaults.conf
  source "$root/config/defaults.conf"
  # shellcheck source=tools.conf
  source "$root/config/tools.conf"
  local_file="$root/config/local.conf"
  if [[ -e "$local_file" ]]; then
    [[ -f "$local_file" && ! -L "$local_file" ]] || { printf 'Unsafe local config type: %s\n' "$local_file" >&2; return 1; }
    owner=$(stat -c '%u' "$local_file"); mode=$(stat -c '%a' "$local_file")
    [[ "$owner" == 0 ]] || { printf 'Local config must be root-owned: %s\n' "$local_file" >&2; return 1; }
    (((8#$mode & 8#022) == 0)) || { printf 'Local config must not be group/other writable: %s\n' "$local_file" >&2; return 1; }
    # Root-owned local configuration is an explicit trust boundary.
    # shellcheck disable=SC1090
    source "$local_file"
  fi
  for key in "${!saved[@]}"; do printf -v "$key" '%s' "${saved[$key]}"; export "${key?}"; done
}
