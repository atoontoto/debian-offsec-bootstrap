#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

VERIFY_REQUIRED_FAILURES=0 VERIFY_WARNINGS=0

verify_manifests() {
  catalog_validate "$PROJECT_ROOT/manifests/tool-catalog.tsv" || { ((VERIFY_REQUIRED_FAILURES+=1)); return 1; }
  "$PROJECT_ROOT/tests/manifest-validation.sh" --quiet || ((VERIFY_REQUIRED_FAILURES+=1))
}

verify_expected_commands() {
  local id category executables profile exe missing
  while IFS=$'\t' read -r id _ category _ _ executables _ _ _ _ _ _ _ _ _ profile _ || [[ -n "$id" ]]; do
    [[ "$id" == id || -z "$id" || "$id" == \#* ]] && continue
    profile_includes "$OFFSEC_PROFILE" "$profile" || continue
    [[ -z ${VERIFY_CATEGORY:-} || "$category" == "$VERIFY_CATEGORY" ]] || continue
    missing=false
    IFS=',' read -r -a exe_list <<< "$executables"
    for exe in "${exe_list[@]}"; do command -v "$exe" >/dev/null 2>&1 || missing=true; done
    if [[ "$missing" == true ]]; then
      if [[ "$profile" == core ]]; then ((VERIFY_REQUIRED_FAILURES+=1)); printf 'FAIL\t%s\tmissing command(s): %s\n' "$id" "$executables"; else ((VERIFY_WARNINGS+=1)); printf 'WARN\t%s\tmissing command(s): %s\n' "$id" "$executables"; fi
    else printf 'OK\t%s\t%s\n' "$id" "$executables"; fi
  done < "$PROJECT_ROOT/manifests/tool-catalog.tsv"
}

write_inventory() {
  local target="$OFFSEC_STATE_ROOT/inventory.json" tmp user
  run install -d -m 0755 "$OFFSEC_STATE_ROOT"
  if [[ "$DRY_RUN" == true ]]; then log_info '[DRY-RUN] would generate and atomically install inventory.json.'; return 0; fi
  new_temp_dir tmp_dir
  # shellcheck disable=SC2154  # assigned by validated pass-by-name helper
  tmp="$tmp_dir/inventory.json"; user=$(invoking_user)
  python3 "$PROJECT_ROOT/scripts/build-inventory.py" --catalog "$PROJECT_ROOT/manifests/tool-catalog.tsv" --profile "$OFFSEC_PROFILE" --output "$tmp" --owner "$user" --github-state "$OFFSEC_STATE_ROOT/github-installed.tsv"
  atomic_install_file "$tmp" "$target" 0644
}

verify_owned_paths() {
  local path
  for path in "$OFFSEC_INSTALL_ROOT" "$OFFSEC_STATE_ROOT" "$OFFSEC_LOG_ROOT"; do
    [[ -e "$path" ]] || continue
    [[ $(stat -c '%U' "$path") == root ]] || { log_warn "$path is not root-owned"; ((VERIFY_WARNINGS+=1)); }
  done
}

verify_symlinks() {
  local link id method executables exe expected_root resolved
  while IFS= read -r -d '' link; do [[ -e "$link" ]] || { log_warn "Broken symlink: $link"; ((VERIFY_WARNINGS+=1)); }; done < <(find /usr/local/bin -maxdepth 1 -type l -name 'offsec-*' -print0 2>/dev/null)
  while IFS=$'\t' read -r id _ _ method _ executables _ || [[ -n "$id" ]]; do
    [[ "$id" == id || -z "$id" || "$id" == \#* ]] && continue
    [[ "$method" =~ ^(go|cargo|github)$ ]] || continue
    expected_root="$OFFSEC_INSTALL_ROOT"
    IFS=',' read -r -a exe_list <<< "$executables"
    for exe in "${exe_list[@]}"; do
      link="/usr/local/bin/$exe"
      if [[ ! -L "$link" ]]; then log_warn "Missing managed command symlink: $link"; ((VERIFY_WARNINGS+=1)); continue; fi
      resolved=$(realpath -m -- "$link")
      path_is_within "$resolved" "$(realpath -m -- "$expected_root")" || { log_warn "Managed command points outside $expected_root: $link"; ((VERIFY_WARNINGS+=1)); continue; }
      [[ -e "$link" ]] || { log_warn "Broken managed command symlink: $link"; ((VERIFY_WARNINGS+=1)); }
    done
  done < "$PROJECT_ROOT/manifests/tool-catalog.tsv"
}
