#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

managed_git_repo() {
  local name="$1" url="$2" ref="$3" target current origin
  target="$OFFSEC_INSTALL_ROOT/resources/$name"
  is_https_url "$url" || die "Git URL must use HTTPS: $url"
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || die "Git resource must use a full commit pin: $name"
  [[ ! -L "$OFFSEC_INSTALL_ROOT/resources" && ! -L "$target" ]] || die "Refusing symlinked managed Git destination: $target"
  ensure_managed_directory "$OFFSEC_INSTALL_ROOT/resources" "$OFFSEC_INSTALL_ROOT"
  if [[ "$DRY_RUN" == true ]]; then record_success "wordlist:$name ($ref)"; return 0; fi
  if [[ -d "$target/.git" ]]; then
    origin=$(env GIT_TERMINAL_PROMPT=0 git -C "$target" remote get-url origin 2>/dev/null || true)
    [[ "$origin" == "$url" ]] || { record_failure "wordlist:$name origin does not match the manifest" false; return; }
    [[ -z $(env GIT_TERMINAL_PROMPT=0 git -C "$target" status --porcelain) ]] || { record_failure "wordlist:$name has local changes or untracked files" false; return; }
  elif [[ ! -e "$target" ]]; then
    run install -d -m 0755 "$target"
    env GIT_TERMINAL_PROMPT=0 git -C "$target" init -q || { record_failure "wordlist:$name initialization" false; return; }
    env GIT_TERMINAL_PROMPT=0 git -C "$target" remote add origin "$url" || { record_failure "wordlist:$name remote setup" false; return; }
  else record_failure "wordlist:$name target exists but is unmanaged" false; return; fi
  env GIT_TERMINAL_PROMPT=0 git -C "$target" fetch --depth 1 origin "$ref" || { record_failure "wordlist:$name fetch" false; return; }
  env GIT_TERMINAL_PROMPT=0 git -C "$target" checkout -q --detach FETCH_HEAD || { record_failure "wordlist:$name checkout" false; return; }
  current=$(env GIT_TERMINAL_PROMPT=0 git -C "$target" rev-parse HEAD 2>/dev/null || true)
  if [[ "$current" == "$ref" ]]; then record_success "wordlist:$name"; else record_failure "wordlist:$name commit verification" false; fi
}

install_wordlists() {
  local name url ref link
  while IFS=$'\t' read -r name url ref link || [[ -n "$name" ]]; do
    [[ "$name" == id || -z "$name" || "$name" == \#* ]] && continue
    managed_git_repo "$name" "$url" "$ref"
  done < "$PROJECT_ROOT/manifests/git-resources.tsv"
  run install -d -m 0755 "$OFFSEC_WORDLIST_ROOT"
  while IFS=$'\t' read -r name url ref link || [[ -n "$name" ]]; do
    [[ "$name" == id || -z "$name" || "$name" == \#* ]] && continue
    if [[ "$DRY_RUN" == true || -d "$OFFSEC_INSTALL_ROOT/resources/$name" ]]; then install_managed_symlink "$OFFSEC_INSTALL_ROOT/resources/$name" "$OFFSEC_WORDLIST_ROOT/$link" "$OFFSEC_INSTALL_ROOT"; fi
  done < "$PROJECT_ROOT/manifests/git-resources.tsv"
  if [[ -f "$OFFSEC_WORDLIST_ROOT/rockyou.txt.gz" && ! -f "$OFFSEC_WORDLIST_ROOT/rockyou.txt" ]]; then
    run gzip -dk "$OFFSEC_WORDLIST_ROOT/rockyou.txt.gz"
    if [[ "$DRY_RUN" == true ]]; then log_info '[DRY-RUN] would record ownership of the decompressed rockyou.txt.'; else
      new_temp_dir marker_dir
      # shellcheck disable=SC2154  # assigned by validated pass-by-name helper
      printf '%s\n' "$OFFSEC_WORDLIST_ROOT/rockyou.txt" > "$marker_dir/rockyou-decompressed"
      atomic_install_file "$marker_dir/rockyou-decompressed" "$OFFSEC_STATE_ROOT/rockyou-decompressed" 0600
    fi
  fi
}
