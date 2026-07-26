#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

cargo_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/cargo-tools.tsv"; }

cargo_install_tool() {
  local id="$1" row crate version features executables user stage exe missing=false required=false
  if catalog_tool_required "$id"; then required=true; fi
  row=$(cargo_manifest_row "$id"); [[ -n "$row" ]] || { record_failure "cargo:$id (missing manifest entry)" "$required"; return; }
  IFS=$'\t' read -r _ crate version features executables <<< "$row"
  if [[ "$DRY_RUN" == true ]]; then record_success "cargo:$id ($crate $version)"; return 0; fi
  user=$(invoking_user); new_temp_dir stage; run chown "$user":"$(id -gn "$user")" "$stage"
  local args=(install --locked --root "$stage" --version "$version" "$crate")
  [[ "$features" != - ]] && args+=(--features "$features")
  if run_as_user "$user" env GIT_TERMINAL_PROMPT=0 cargo "${args[@]}"; then
    ensure_managed_directory "$OFFSEC_INSTALL_ROOT/cargo/bin" "$OFFSEC_INSTALL_ROOT"
    IFS=',' read -r -a exe_list <<< "$executables"
    for exe in "${exe_list[@]}"; do
      if [[ ! -x "$stage/bin/$exe" ]]; then missing=true; continue; fi
      run install -m 0755 "$stage/bin/$exe" "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe"
      install_managed_symlink "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe" "/usr/local/bin/$exe" "$OFFSEC_INSTALL_ROOT"
    done
    if [[ "$missing" == true ]]; then record_failure "cargo:$id (one or more expected executables were not built)" "$required"; else record_success "cargo:$id"; fi
  else record_failure "cargo:$id" "$required"; fi
}

cargo_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; cargo_install_tool "$id"; done < <(catalog_rows cargo "$category")
}
