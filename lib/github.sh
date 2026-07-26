#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

github_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/github-tools.tsv"; }

github_asset_metadata() {
  local repo="$1" tag="$2" regex="$3" api
  api="https://api.github.com/repos/$repo/releases/tags/$tag"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$api" | jq -r --arg re "$regex" 'first(.assets[] | select(.name|test($re)) | [.name,.browser_download_url]) | @tsv'
}

github_install_tool() {
  local id="$1" row repo tag regex checksum_url executables metadata name url tmp archive sumfile expected dest backup exe source state_tmp missing=false required=false
  if catalog_tool_required "$id"; then required=true; fi
  row=$(github_manifest_row "$id"); [[ -n "$row" ]] || { record_failure "github:$id (missing manifest entry)" "$required"; return; }
  IFS=$'\t' read -r _ repo tag regex checksum_url executables _ <<< "$row"
  [[ "$checksum_url" != - ]] || { record_failure "github:$id (upstream checksum not configured)" "$required"; return; }
  if [[ "$DRY_RUN" == true ]]; then record_success "github:$id ($repo $tag, checksum required)"; return 0; fi
  metadata=$(github_asset_metadata "$repo" "$tag" "$regex") || { record_failure "github:$id release lookup" "$required"; return; }
  IFS=$'\t' read -r name url <<< "$metadata"; new_temp_dir tmp; archive="$tmp/$name"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && -n "$url" ]] || { record_failure "github:$id invalid release asset metadata" "$required"; return; }
  download_https "$url" "$archive" || { record_failure "github:$id asset download" "$required"; return; }
  if [[ "$checksum_url" != - ]]; then
    checksum_url=${checksum_url//\{asset\}/$name}; sumfile="$tmp/checksums.txt"
    download_https "$checksum_url" "$sumfile" || { record_failure "github:$id checksum download" "$required"; return; }
    expected=$(awk -v n="$name" '$2 == n || $2 == "*" n {print $1; exit}' "$sumfile")
    verify_sha256 "$archive" "$expected" || { record_failure "github:$id checksum" "$required"; return; }
  fi
  source="$tmp/extract"; extract_archive "$archive" "$source"; dest="$OFFSEC_INSTALL_ROOT/tools/$id/$tag"; backup="$OFFSEC_INSTALL_ROOT/tools/$id/.previous-$tag"
  ensure_managed_directory "$(dirname "$dest")" "$OFFSEC_INSTALL_ROOT"
  if [[ -d "$backup" ]]; then
    if [[ ! -e "$dest" ]]; then run mv -- "$backup" "$dest"; else safe_remove_tree "$backup" "$OFFSEC_INSTALL_ROOT"; fi
  fi
  [[ ! -L "$dest" && ( ! -e "$dest" || -d "$dest" ) ]] || { record_failure "github:$id unsafe existing destination" "$required"; return; }
  if [[ -d "$dest" ]]; then run mv -- "$dest" "$backup"; fi
  if ! run mv -- "$source" "$dest"; then
    if [[ -d "$backup" ]]; then run mv -- "$backup" "$dest"; fi
    record_failure "github:$id activation" "$required"
    return
  fi
  if [[ -d "$backup" ]]; then safe_remove_tree "$backup" "$OFFSEC_INSTALL_ROOT"; fi
  install_managed_symlink "$dest" "$OFFSEC_INSTALL_ROOT/tools/$id/current" "$OFFSEC_INSTALL_ROOT"
  IFS=',' read -r -a exe_list <<< "$executables"
  for exe in "${exe_list[@]}"; do
    local found; found=$(find "$dest" -type f -name "$exe" -print -quit)
    if [[ -n "$found" ]]; then install_managed_symlink "$found" "/usr/local/bin/$exe" "$OFFSEC_INSTALL_ROOT"; else missing=true; fi
  done
  new_temp_dir state_tmp_dir
  # shellcheck disable=SC2154  # assigned by validated pass-by-name helper
  state_tmp="$state_tmp_dir/github-installed.tsv"
  if [[ -f "$OFFSEC_STATE_ROOT/github-installed.tsv" ]]; then awk -F '\t' -v wanted="$id" '$1 != wanted' "$OFFSEC_STATE_ROOT/github-installed.tsv" > "$state_tmp"; fi
  printf '%s\t%s\t%s\n' "$id" "$tag" "$url" >> "$state_tmp"
  atomic_install_file "$state_tmp" "$OFFSEC_STATE_ROOT/github-installed.tsv" 0644
  if [[ "$missing" == true ]]; then record_failure "github:$id (one or more expected executables were absent)" "$required"; else record_success "github:$id"; fi
}

github_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; github_install_tool "$id"; done < <(catalog_rows github "$category")
}
