#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

go_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/go-tools.tsv"; }

go_install_tool() {
  local id="$1" row module version executables user tmp exe missing=false required=false
  if catalog_tool_required "$id"; then required=true; fi
  row=$(go_manifest_row "$id"); [[ -n "$row" ]] || { record_failure "go:$id (missing manifest entry)" "$required"; return; }
  IFS=$'\t' read -r _ module version executables <<< "$row"
  [[ "$version" != latest || "$OFFSEC_UPDATE_CHANNEL" == latest ]] || { record_skip "go:$id latest is disabled on stable channel"; return; }
  if [[ "$DRY_RUN" == true ]]; then record_success "go:$id ($module@$version)"; return 0; fi
  user=$(invoking_user); new_temp_dir tmp; run chown "$user":"$(id -gn "$user")" "$tmp"
  if run_as_user "$user" env GIT_TERMINAL_PROMPT=0 GOBIN="$tmp" GO111MODULE=on go install "${module}@${version}"; then
    ensure_managed_directory "$OFFSEC_INSTALL_ROOT/go/bin" "$OFFSEC_INSTALL_ROOT"
    IFS=',' read -r -a exe_list <<< "$executables"
    for exe in "${exe_list[@]}"; do
      if [[ ! -x "$tmp/$exe" ]]; then missing=true; continue; fi
      run install -m 0755 "$tmp/$exe" "$OFFSEC_INSTALL_ROOT/go/bin/$exe"
      install_managed_symlink "$OFFSEC_INSTALL_ROOT/go/bin/$exe" "/usr/local/bin/$exe" "$OFFSEC_INSTALL_ROOT"
    done
    if [[ "$missing" == true ]]; then record_failure "go:$id (one or more expected executables were not built)" "$required"; else record_success "go:$id"; fi
  else record_failure "go:$id" "$required"; fi
}

go_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; go_install_tool "$id"; done < <(catalog_rows go "$category")
}
