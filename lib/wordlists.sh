#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

managed_git_repo() {
  local name="$1" url="$2" ref="$3" target
  target="$OFFSEC_INSTALL_ROOT/resources/$name"
  is_https_url "$url" || die "Git URL must use HTTPS: $url"
  run install -d -m 0755 "$OFFSEC_INSTALL_ROOT/resources"
  if [[ -d "$target/.git" ]]; then
    run git -C "$target" fetch --prune origin "$ref"
    run git -C "$target" merge --ff-only "origin/$ref"
  elif [[ ! -e "$target" ]]; then run git clone --filter=blob:none --depth 1 --branch "$ref" -- "$url" "$target"
  else record_failure "wordlist:$name target exists but is unmanaged" false; return; fi
  run git -C "$target" rev-parse HEAD
  record_success "wordlist:$name"
}

install_wordlists() {
  managed_git_repo SecLists https://github.com/danielmiessler/SecLists.git master
  managed_git_repo PayloadsAllTheThings https://github.com/swisskyrepo/PayloadsAllTheThings.git master
  run install -d -m 0755 "$OFFSEC_WORDLIST_ROOT"
  run ln -sfn "$OFFSEC_INSTALL_ROOT/resources/SecLists" "$OFFSEC_WORDLIST_ROOT/seclists"
  run ln -sfn "$OFFSEC_INSTALL_ROOT/resources/PayloadsAllTheThings" "$OFFSEC_WORDLIST_ROOT/payloadsallthethings"
  if [[ -f /usr/share/wordlists/rockyou.txt.gz && ! -f /usr/share/wordlists/rockyou.txt ]]; then run gzip -dk /usr/share/wordlists/rockyou.txt.gz; fi
}
