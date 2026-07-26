#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/probe"
cat > "$tmp/os-release" <<'EOF'
ID=debian
VERSION_ID="13"
VERSION_CODENAME=trixie
EOF

id() {
  case "${1:-}" in
    -u) if [[ $# -eq 1 || ${2:-} == root ]]; then printf '0\n'; else command id "$@"; fi ;;
    -un) printf 'root\n' ;;
    -g) printf '0\n' ;;
    -gn) printf 'root\n' ;;
    *) command id "$@" ;;
  esac
}
apt-cache() { return 0; }
dpkg() { if [[ "${1:-}" == --audit ]]; then return 0; else command dpkg "$@"; fi; }
getent() { if [[ "$1" == passwd && "$2" == root ]]; then printf 'root:x:0:0:root:/root:/bin/bash\n'; else command getent "$@"; fi; }
export -f id apt-cache dpkg getent

before=$(find "$tmp/probe" -mindepth 1 -print | sort)
environment=(
  "OFFSEC_OS_RELEASE_FILE=$tmp/os-release" OFFSEC_TEST_ARCH=amd64
  "OFFSEC_INSTALL_ROOT=$tmp/probe/install root" "OFFSEC_WORDLIST_ROOT=$tmp/probe/word lists"
  "OFFSEC_STATE_ROOT=$tmp/probe/state" "OFFSEC_LOG_ROOT=$tmp/probe/log" OFFSEC_MIN_FREE_GIB=1
  OFFSEC_INSTALL_BURP=false OFFSEC_INSTALL_BLOODHOUND=false OFFSEC_INSTALL_WORDLISTS=false
  OFFSEC_INSTALL_CLOUD=false OFFSEC_DESKTOP=none OFFSEC_PROFILE=core
)
env "${environment[@]}" bash "$ROOT/install.sh" --categories base --dry-run --non-interactive >/dev/null 2>&1
env "${environment[@]}" bash "$ROOT/update.sh" --tools-only --dry-run --non-interactive >/dev/null 2>&1
env "${environment[@]}" bash "$ROOT/uninstall.sh" --all --dry-run >/dev/null 2>&1
after=$(find "$tmp/probe" -mindepth 1 -print | sort)
[[ "$before" == "$after" ]]
printf 'Mocked install/update/uninstall dry-runs made no filesystem changes.\n'
