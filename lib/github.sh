#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

github_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/github-tools.tsv"; }

github_asset_metadata() {
  local repo="$1" tag="$2" regex="$3" api
  api="https://api.github.com/repos/$repo/releases/tags/$tag"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$api" | jq -r --arg re "$regex" '.assets[] | select(.name|test($re)) | [.name,.browser_download_url] | @tsv' | head -n1
}

github_install_tool() {
  local id="$1" row repo tag regex checksum_url executables metadata name url tmp archive sumfile expected dest previous exe source
  row=$(github_manifest_row "$id"); [[ -n "$row" ]] || { record_failure "github:$id (missing manifest entry)" false; return; }
  IFS=$'\t' read -r _ repo tag regex checksum_url executables _ <<< "$row"
  metadata=$(github_asset_metadata "$repo" "$tag" "$regex") || { record_failure "github:$id release lookup" false; return; }
  IFS=$'\t' read -r name url <<< "$metadata"; new_temp_dir tmp; archive="$tmp/$name"
  download_https "$url" "$archive"
  if [[ "$checksum_url" != - ]]; then
    checksum_url=${checksum_url//\{asset\}/$name}; sumfile="$tmp/checksums.txt"; download_https "$checksum_url" "$sumfile"
    expected=$(awk -v n="$name" '$0 ~ n {print $1; exit}' "$sumfile")
    verify_sha256 "$archive" "$expected" || { record_failure "github:$id checksum" false; return; }
  else
    record_skip "github:$id (upstream checksum not configured)"; return
  fi
  source="$tmp/extract"; extract_archive "$archive" "$source"; dest="$OFFSEC_INSTALL_ROOT/tools/$id/$tag"; previous="$OFFSEC_INSTALL_ROOT/tools/$id/previous"
  run install -d -m 0755 "$(dirname "$dest")"
  [[ -d "$dest" ]] && safe_remove_tree "$dest" "$OFFSEC_INSTALL_ROOT"
  run mv -- "$source" "$dest"
  run ln -sfn "$tag" "$OFFSEC_INSTALL_ROOT/tools/$id/current"
  IFS=',' read -r -a exe_list <<< "$executables"
  for exe in "${exe_list[@]}"; do
    local found; found=$(find "$dest" -type f -name "$exe" -print -quit)
    [[ -n "$found" ]] && run ln -sfn "$found" "/usr/local/bin/$exe"
  done
  printf '%s\t%s\t%s\n' "$id" "$tag" "$url" >> "$OFFSEC_STATE_ROOT/github-installed.tsv"
  [[ -L "$previous" ]] || true
  record_success "github:$id"
}

github_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; github_install_tool "$id"; done < <(catalog_rows github "$category")
}
