#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

cargo_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/cargo-tools.tsv"; }

cargo_install_tool() {
  local id="$1" row crate version features executables user stage exe
  row=$(cargo_manifest_row "$id"); [[ -n "$row" ]] || { record_failure "cargo:$id (missing manifest entry)" false; return; }
  IFS=$'\t' read -r _ crate version features executables <<< "$row"
  user=$(invoking_user); new_temp_dir stage; run chown "$user":"$(id -gn "$user")" "$stage"
  local args=(install --locked --root "$stage" --version "$version" "$crate")
  [[ "$features" != - ]] && args+=(--features "$features")
  if run_as_user "$user" cargo "${args[@]}"; then
    run install -d -m 0755 "$OFFSEC_INSTALL_ROOT/cargo/bin"
    IFS=',' read -r -a exe_list <<< "$executables"
    for exe in "${exe_list[@]}"; do
      [[ -x "$stage/bin/$exe" ]] || continue
      run install -m 0755 "$stage/bin/$exe" "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe"
      run ln -sfn "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe" "/usr/local/bin/$exe"
    done
    record_success "cargo:$id"
  else record_failure "cargo:$id" false; fi
}

cargo_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; cargo_install_tool "$id"; done < <(catalog_rows cargo "$category")
}
