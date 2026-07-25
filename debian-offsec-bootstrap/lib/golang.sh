#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

go_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/go-tools.tsv"; }

go_install_tool() {
  local id="$1" row module version executables user tmp exe
  row=$(go_manifest_row "$id"); [[ -n "$row" ]] || { record_failure "go:$id (missing manifest entry)" false; return; }
  IFS=$'\t' read -r _ module version executables <<< "$row"
  [[ "$version" != latest || "$OFFSEC_UPDATE_CHANNEL" == latest ]] || { record_skip "go:$id latest is disabled on stable channel"; return; }
  user=$(invoking_user); new_temp_dir tmp; run chown "$user":"$(id -gn "$user")" "$tmp"
  if run_as_user "$user" env GOBIN="$tmp" GO111MODULE=on go install "${module}@${version}"; then
    run install -d -m 0755 "$OFFSEC_INSTALL_ROOT/go/bin"
    IFS=',' read -r -a exe_list <<< "$executables"
    for exe in "${exe_list[@]}"; do
      [[ -x "$tmp/$exe" ]] || continue
      run install -m 0755 "$tmp/$exe" "$OFFSEC_INSTALL_ROOT/go/bin/$exe"
      run ln -sfn "$OFFSEC_INSTALL_ROOT/go/bin/$exe" "/usr/local/bin/$exe"
    done
    record_success "go:$id"
  else record_failure "go:$id" false; fi
}

go_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; go_install_tool "$id"; done < <(catalog_rows go "$category")
}
