#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

pipx_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/pipx-tools.txt"; }

pipx_install_tool() {
  local id="$1" user row package version inject spec
  user=$(invoking_user); row=$(pipx_manifest_row "$id")
  [[ -n "$row" ]] || { record_failure "pipx:$id (missing manifest entry)" false; return; }
  IFS=$'\t' read -r _ package version inject _ <<< "$row"
  if [[ "$package" == git+https://* ]]; then
    [[ "$package" =~ ^git\+https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$ ]] || { record_failure "pipx:$id unsafe source URL" false; return; }
    [[ "$version" != latest ]] || { record_failure "pipx:$id Git source must be pinned" false; return; }
    spec="${package}@${version}"
  else
    spec="$package"; [[ "$version" != latest ]] && spec+="==$version"
  fi
  if run_as_user "$user" env PIPX_HOME="$(user_home "$user")/.local/share/pipx" PIPX_BIN_DIR="$(user_home "$user")/.local/bin" pipx install --force "$spec"; then
    if [[ "$inject" != - ]]; then run_as_user "$user" pipx inject "$package" "$inject" || log_warn "Optional injection failed for $id"; fi
    record_success "pipx:$id"
  else record_failure "pipx:$id" false; fi
}

pipx_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; pipx_install_tool "$id"; done < <(catalog_rows pipx "$category")
}

pipx_upgrade_all() {
  local user
  user=$(invoking_user)
  run_as_user "$user" pipx upgrade-all --include-injected || record_failure 'pipx:upgrade-all' false
}

pipx_upgrade_tool() {
  local id="$1" row package user
  row=$(pipx_manifest_row "$id"); [[ -n "$row" ]] || { record_failure "pipx:$id missing manifest entry" false; return; }
  IFS=$'\t' read -r _ package _ <<< "$row"; user=$(invoking_user)
  if run_as_user "$user" pipx upgrade "$id" --include-injected; then record_success "pipx:$id"; else record_failure "pipx:$id upgrade" false; fi
}

pipx_verify() {
  local user; user=$(invoking_user)
  run_as_user "$user" pipx list --json >/dev/null
}
