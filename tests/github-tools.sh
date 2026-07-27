#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT/tests/testlib.sh"
source "$ROOT/lib/logging.sh"; source "$ROOT/lib/common.sh"; source "$ROOT/lib/catalog.sh"; source "$ROOT/lib/github.sh"; source "$ROOT/lib/golang.sh"
if ! python3 -c 'import sys' >/dev/null 2>&1; then python3() { python "$@"; }; fi
skip() { TESTS=$((TESTS+1)); printf 'ok %d - %s # SKIP\n' "$TESTS" "$1"; }
PROJECT_ROOT=$ROOT; OFFSEC_PROFILE=standard; SELECTED_CATEGORIES=network; DETECTED_ARCH=amd64
DRY_RUN=false; OFFSEC_UPDATE_CHANNEL=stable
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
OFFSEC_INSTALL_ROOT="$tmp/install"; OFFSEC_STATE_ROOT="$tmp/state"; OFFSEC_COMMAND_ROOT="$tmp/bin"
mkdir -p "$OFFSEC_INSTALL_ROOT" "$OFFSEC_STATE_ROOT" "$OFFSEC_COMMAND_ROOT" "$tmp/assets/proxy" "$tmp/assets/agent"
touch "$tmp/link-target"
ln -s "$tmp/link-target" "$tmp/link-probe" 2>/dev/null || true
if [[ -L "$tmp/link-probe" ]]; then native_symlinks=true; else native_symlinks=false; fi
rm -f "$tmp/link-probe" "$tmp/link-target"
cp "$ROOT/tests/fixtures/ligolo-ng/proxy" "$tmp/assets/proxy/proxy"
cp "$ROOT/tests/fixtures/ligolo-ng/agent" "$tmp/assets/agent/agent"
chmod 0755 "$tmp/assets/proxy/proxy" "$tmp/assets/agent/agent"
printf 'fixture\n' > "$tmp/assets/proxy/README.md"
printf 'fixture\n' > "$tmp/assets/agent/README.md"
PROXY_ARCHIVE="$tmp/proxy.tar.gz"; AGENT_ARCHIVE="$tmp/agent.tar.gz"; CHECKSUM_FILE="$tmp/checksums.txt"
tar -czf "$PROXY_ARCHIVE" -C "$tmp/assets/proxy" proxy README.md
tar -czf "$AGENT_ARCHIVE" -C "$tmp/assets/agent" agent README.md
make_checksums() {
  printf '%s  ligolo-ng_proxy_0.8.3_linux_amd64.tar.gz\n' "$(sha256sum "$PROXY_ARCHIVE" | awk '{print $1}')" > "$CHECKSUM_FILE"
  printf '%s  ligolo-ng_agent_0.8.3_linux_amd64.tar.gz\n' "$(sha256sum "$AGENT_ARCHIVE" | awk '{print $1}')" >> "$CHECKSUM_FILE"
}
make_checksums

github_asset_metadata() {
  local repo="$1" tag="$2" regex="$3" name
  if [[ "$regex" == *proxy* ]]; then name=ligolo-ng_proxy_0.8.3_linux_amd64.tar.gz; else name=ligolo-ng_agent_0.8.3_linux_amd64.tar.gz; fi
  printf '%s\thttps://github.com/%s/releases/download/%s/%s\n' "$name" "$repo" "$tag" "$name"
}
download_https() {
  local url="$1" destination="$2"
  printf '%s\n' "$url" >> "$tmp/downloads.log"
  case "$url" in
    *checksums.txt) cp "$CHECKSUM_FILE" "$destination" ;;
    *proxy*) cp "$PROXY_ARCHIVE" "$destination" ;;
    *agent*) cp "$AGENT_ARCHIVE" "$destination" ;;
    *) return 1 ;;
  esac
}
chown() { :; }

catalog_row=$(awk -F '\t' '$1=="ligolo-ng" {print}' "$ROOT/manifests/tool-catalog.tsv")
[[ -n "$catalog_row" ]] && pass 'Ligolo-ng catalog row exists' || fail 'Ligolo-ng catalog row exists'
[[ $(awk -F '\t' '$1=="ligolo-ng" {print $3":"$4":"$6":"$16}' "$ROOT/manifests/tool-catalog.tsv") == 'network:github:ligolo-proxy,ligolo-agent:standard' ]] && pass 'Ligolo-ng catalog metadata selects both standard network commands' || fail 'Ligolo-ng catalog metadata selects both standard network commands'
[[ $(grep -c '^ligolo-ng' "$ROOT/manifests/github-tools.tsv") == 2 ]] && pass 'Ligolo-ng has two component manifest rows' || fail 'Ligolo-ng has two component manifest rows'
grep -Fq $'proxy:ligolo-proxy\t0\t-version' "$ROOT/manifests/github-tools.tsv" && pass 'proxy rename mapping is declared' || fail 'proxy rename mapping is declared'
grep -Fq $'agent:ligolo-agent\t0\t-version' "$ROOT/manifests/github-tools.tsv" && pass 'agent rename mapping is declared' || fail 'agent rename mapping is declared'
grep -Fq 'https://github.com/nicocha30/ligolo-ng/releases/download/v0.8.3/ligolo-ng_0.8.3_checksums.txt' "$ROOT/manifests/github-tools.tsv" && pass 'official pinned checksum URL is declared' || fail 'official pinned checksum URL is declared'

release_json='{"assets":[{"name":"ligolo-ng_proxy_0.8.3_linux_amd64.tar.gz","browser_download_url":"https://example/proxy"},{"name":"ligolo-ng_agent_0.8.3_linux_amd64.tar.gz","browser_download_url":"https://example/agent"}]}'
selected=$(printf '%s' "$release_json" | github_select_asset '^ligolo-ng_proxy_0[.]8[.]3_linux_amd64[.]tar[.]gz$')
[[ "$selected" == $'ligolo-ng_proxy_0.8.3_linux_amd64.tar.gz\thttps://example/proxy' ]] && pass 'AMD64 asset selection is exact' || fail 'AMD64 asset selection is exact'
if printf '%s' "$release_json" | github_select_asset 'linux_amd64' >/dev/null 2>&1; then fail 'ambiguous asset regex is rejected'; else pass 'ambiguous asset regex is rejected'; fi
expected=$(github_checksum_for_asset "$CHECKSUM_FILE" ligolo-ng_proxy_0.8.3_linux_amd64.tar.gz)
assert 'checksum entry is selected exactly' verify_sha256 "$PROXY_ARCHIVE" "$expected"
if github_checksum_for_asset "$CHECKSUM_FILE" absent.tar.gz >/dev/null; then fail 'missing checksum entry is rejected'; else pass 'missing checksum entry is rejected'; fi
if verify_sha256 "$PROXY_ARCHIVE" '0000000000000000000000000000000000000000000000000000000000000000'; then fail 'mismatched checksum is rejected'; else pass 'mismatched checksum is rejected'; fi
cp "$CHECKSUM_FILE" "$tmp/ambiguous-checksums.txt"; head -n 1 "$CHECKSUM_FILE" >> "$tmp/ambiguous-checksums.txt"
if github_checksum_for_asset "$tmp/ambiguous-checksums.txt" ligolo-ng_proxy_0.8.3_linux_amd64.tar.gz >/dev/null; then fail 'ambiguous checksum entry is rejected'; else pass 'ambiguous checksum entry is rejected'; fi

DRY_RUN=true; : > "$tmp/downloads.log"; before=$(find "$OFFSEC_INSTALL_ROOT" "$OFFSEC_STATE_ROOT" "$OFFSEC_COMMAND_ROOT" -mindepth 1 -print | sort)
dry_output=$(github_install_tool ligolo-ng)
after=$(find "$OFFSEC_INSTALL_ROOT" "$OFFSEC_STATE_ROOT" "$OFFSEC_COMMAND_ROOT" -mindepth 1 -print | sort)
[[ "$before" == "$after" && ! -s "$tmp/downloads.log" && "$dry_output" == *ligolo-ng-proxy* && "$dry_output" == *ligolo-ng-agent* ]] && pass 'Ligolo-ng dry-run names both components without downloads or mutation' || fail 'Ligolo-ng dry-run names both components without downloads or mutation'
DRY_RUN=false

DETECTED_ARCH=arm64; before_failures=${#OFFSEC_FAILED_OPTIONAL[@]}; github_install_tool ligolo-ng >/dev/null 2>&1
[[ ${#OFFSEC_FAILED_OPTIONAL[@]} == $((before_failures+1)) ]] && pass 'unsupported architecture fails safely' || fail 'unsupported architecture fails safely'
DETECTED_ARCH=amd64

saved_proxy=$PROXY_ARCHIVE; tar -czf "$tmp/missing-proxy.tar.gz" -C "$tmp/assets/proxy" README.md; PROXY_ARCHIVE="$tmp/missing-proxy.tar.gz"; make_checksums
before_failures=${#OFFSEC_FAILED_OPTIONAL[@]}; github_install_tool ligolo-ng >/dev/null 2>&1
[[ ${#OFFSEC_FAILED_OPTIONAL[@]} == $((before_failures+1)) ]] && pass 'missing proxy binary fails before activation' || fail 'missing proxy binary fails before activation'
PROXY_ARCHIVE=$saved_proxy
saved_agent=$AGENT_ARCHIVE; tar -czf "$tmp/missing-agent.tar.gz" -C "$tmp/assets/agent" README.md; AGENT_ARCHIVE="$tmp/missing-agent.tar.gz"; make_checksums
before_failures=${#OFFSEC_FAILED_OPTIONAL[@]}; github_install_tool ligolo-ng >/dev/null 2>&1
[[ ${#OFFSEC_FAILED_OPTIONAL[@]} == $((before_failures+1)) ]] && pass 'missing agent binary fails before activation' || fail 'missing agent binary fails before activation'
AGENT_ARCHIVE=$saved_agent; make_checksums

if [[ "$native_symlinks" == true ]]; then
  FAKE_LIGOLO_LOG="$tmp/version.log"; export FAKE_LIGOLO_LOG
  github_install_tool ligolo-ng >/dev/null
  [[ -x "$OFFSEC_INSTALL_ROOT/tools/ligolo-ng/v0.8.3/proxy" && -x "$OFFSEC_INSTALL_ROOT/tools/ligolo-ng/v0.8.3/agent" ]] && pass 'both Ligolo-ng components share one versioned layout' || fail 'both Ligolo-ng components share one versioned layout'
  [[ -L "$OFFSEC_COMMAND_ROOT/ligolo-proxy" && -L "$OFFSEC_COMMAND_ROOT/ligolo-agent" ]] && pass 'rename mappings expose both Ligolo-ng commands' || fail 'rename mappings expose both Ligolo-ng commands'
  [[ ! -e "$OFFSEC_COMMAND_ROOT/proxy" && ! -L "$OFFSEC_COMMAND_ROOT/proxy" && ! -e "$OFFSEC_COMMAND_ROOT/agent" && ! -L "$OFFSEC_COMMAND_ROOT/agent" ]] && pass 'generic proxy and agent commands are never created' || fail 'generic proxy and agent commands are never created'
  [[ $(grep -vc $'\t-version$' "$FAKE_LIGOLO_LOG" || true) == 0 ]] && pass 'verification invokes version flags only and starts no listener' || fail 'verification invokes version flags only and starts no listener'
  touch "$OFFSEC_INSTALL_ROOT/tools/ligolo-ng/v0.8.3/old-marker"
  FAIL_ACTIVE_AGENT=true; export FAIL_ACTIVE_AGENT; before_failures=${#OFFSEC_FAILED_OPTIONAL[@]}; github_install_tool ligolo-ng >/dev/null 2>&1; unset FAIL_ACTIVE_AGENT
  [[ ${#OFFSEC_FAILED_OPTIONAL[@]} == $((before_failures+1)) && -e "$OFFSEC_INSTALL_ROOT/tools/ligolo-ng/v0.8.3/old-marker" ]] && pass 'partial activation failure restores the previous version' || fail 'partial activation failure restores the previous version'
  github_install_tool ligolo-ng >/dev/null
  [[ $(grep -c '^ligolo-ng' "$OFFSEC_STATE_ROOT/github-installed.tsv") == 1 ]] && pass 'reinstallation is idempotent in installed state' || fail 'reinstallation is idempotent in installed state'
else
  skip 'versioned layout activation requires native symlink support'
  skip 'rename symlink activation requires native symlink support'
  [[ ! -e "$OFFSEC_COMMAND_ROOT/proxy" && ! -e "$OFFSEC_COMMAND_ROOT/agent" ]] && pass 'generic proxy and agent commands are never created' || fail 'generic proxy and agent commands are never created'
  skip 'post-activation version verification requires native symlink support'
  skip 'partial activation rollback requires native symlink support'
  skip 'reinstallation activation requires native symlink support'
  mkdir -p "$OFFSEC_INSTALL_ROOT/tools/ligolo-ng/v0.8.3"
  install -m 0755 "$ROOT/tests/fixtures/ligolo-ng/proxy" "$OFFSEC_INSTALL_ROOT/tools/ligolo-ng/v0.8.3/proxy"
  install -m 0755 "$ROOT/tests/fixtures/ligolo-ng/agent" "$OFFSEC_INSTALL_ROOT/tools/ligolo-ng/v0.8.3/agent"
  install -m 0755 "$ROOT/tests/fixtures/ligolo-ng/proxy" "$OFFSEC_COMMAND_ROOT/ligolo-proxy"
  install -m 0755 "$ROOT/tests/fixtures/ligolo-ng/agent" "$OFFSEC_COMMAND_ROOT/ligolo-agent"
  printf 'ligolo-ng\tv0.8.3\thttps://github.com/nicocha30/ligolo-ng/releases/tag/v0.8.3\thttps://github.com/nicocha30/ligolo-ng/releases/download/v0.8.3/ligolo-ng_0.8.3_checksums.txt\tfixtures\n' > "$OFFSEC_STATE_ROOT/github-installed.tsv"
fi

PATH="$OFFSEC_COMMAND_ROOT:$PATH" python3 "$ROOT/scripts/build-inventory.py" --catalog "$ROOT/manifests/tool-catalog.tsv" --profile standard --category network --owner tester --github-state "$OFFSEC_STATE_ROOT/github-installed.tsv" --output "$tmp/inventory.json"
python3 - "$tmp/inventory.json" "$native_symlinks" <<'PY' && pass 'inventory records both Ligolo-ng commands, pin, source, and verified state' || fail 'inventory records both Ligolo-ng commands, pin, source, and verified state'
import json, sys
d=json.load(open(sys.argv[1], encoding='utf-8'))
t=next(t for t in d['tools'] if t['id']=='ligolo-ng')
assert [e['name'] for e in t['executables']]==['ligolo-proxy','ligolo-agent']
assert t['pinned_version']=='v0.8.3' and t['verified_source']
if sys.argv[2]=='true': assert t['installed'] and not t['partial']
assert t['release_source']=='https://github.com/nicocha30/ligolo-ng/releases/tag/v0.8.3'
PY

chisel_catalog=$(awk -F '\t' '$1=="chisel" {print $3":"$4":"$6":"$10":"$11":"$16}' "$ROOT/manifests/tool-catalog.tsv")
[[ "$chisel_catalog" == 'network:go:chisel:false:optional:standard' ]] && pass 'Chisel catalog row is standard, network-scoped, and optional-service capable' || fail 'Chisel catalog row is standard, network-scoped, and optional-service capable'
chisel_manifest=$(awk -F '\t' '$1=="chisel" {print $2":"$3":"$4}' "$ROOT/manifests/go-tools.tsv")
[[ "$chisel_manifest" == 'github.com/jpillora/chisel:v1.11.5:chisel' ]] && pass 'Chisel uses the official module, pinned version, and command name' || fail 'Chisel uses the official module, pinned version, and command name'
DRY_RUN=true; chisel_dry=$(go_install_tool chisel)
[[ "$chisel_dry" == *'github.com/jpillora/chisel@v1.11.5'* ]] && pass 'Chisel dry-run shows the pinned Go installation' || fail 'Chisel dry-run shows the pinned Go installation'
DRY_RUN=false
python3 - "$tmp/inventory.json" <<'PY' && pass 'inventory records the pinned Chisel source' || fail 'inventory records the pinned Chisel source'
import json, sys
d=json.load(open(sys.argv[1], encoding='utf-8'))
t=next(t for t in d['tools'] if t['id']=='chisel')
assert t['pinned_version']=='v1.11.5' and t['release_source']=='github.com/jpillora/chisel@v1.11.5'
PY
! rg -n -i 'chisel.*(systemctl|service)|(systemctl|service).*chisel' "$ROOT/systemd" "$ROOT/install.sh" "$ROOT/update.sh" >/dev/null && pass 'no Chisel service is created or started' || fail 'no Chisel service is created or started'
grep -Fq 'go|cargo|github)' "$ROOT/uninstall.sh" && grep -Fq 'rm -f -- "$OFFSEC_INSTALL_ROOT/go/bin/$exe"' "$ROOT/uninstall.sh" && pass 'Chisel uninstall uses only the managed Go executable path' || fail 'Chisel uninstall uses only the managed Go executable path'

finish
