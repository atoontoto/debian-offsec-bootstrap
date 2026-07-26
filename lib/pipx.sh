#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

pipx_manifest_row() { awk -F '\t' -v id="$1" '$1==id {print; exit}' "$PROJECT_ROOT/manifests/pipx-tools.txt"; }

pipx_install_tool() {
  local id="$1" user row package version inject executables spec home exe missing=false required=false
  if catalog_tool_required "$id"; then required=true; fi
  user=$(invoking_user); row=$(pipx_manifest_row "$id")
  [[ -n "$row" ]] || { record_failure "pipx:$id (missing manifest entry)" "$required"; return; }
  IFS=$'\t' read -r _ package version inject executables <<< "$row"
  if [[ "$package" == git+https://* ]]; then
    [[ "$package" =~ ^git\+https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$ ]] || { record_failure "pipx:$id unsafe source URL" "$required"; return; }
    [[ "$version" != latest ]] || { record_failure "pipx:$id Git source must be pinned" "$required"; return; }
    spec="${package}@${version}"
  else
    if [[ "$version" == latest && "$OFFSEC_UPDATE_CHANNEL" != latest ]]; then record_failure "pipx:$id latest is disabled on stable channel" "$required"; return; fi
    spec="$package"; [[ "$version" != latest ]] && spec+="==$version"
  fi
  home=$(user_home "$user")
  if run_as_user "$user" env GIT_TERMINAL_PROMPT=0 PIPX_HOME="$home/.local/share/pipx" PIPX_BIN_DIR="$home/.local/bin" pipx install --force "$spec"; then
    if [[ "$inject" != - ]]; then run_as_user "$user" pipx inject "$package" "$inject" || log_warn "Optional injection failed for $id"; fi
    if [[ "$DRY_RUN" == false ]]; then
      IFS=',' read -r -a exe_list <<< "$executables"
      for exe in "${exe_list[@]}"; do [[ -x "$home/.local/bin/$exe" ]] || missing=true; done
    fi
    if [[ "$missing" == true ]]; then record_failure "pipx:$id (expected executable missing: $executables)" "$required"; else record_success "pipx:$id"; fi
  else record_failure "pipx:$id" "$required"; fi
}

pipx_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; pipx_install_tool "$id"; done < <(catalog_rows pipx "$category")
}

pipx_upgrade_all() {
  local row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; pipx_install_tool "$id"; done < <(catalog_rows pipx '')
}

pipx_upgrade_tool() {
  pipx_install_tool "$1"
}

pipx_verify() {
  local user; user=$(invoking_user)
  run_as_user "$user" pipx list --json >/dev/null
}

pipx_environment_exists() {
  local user="$1" id="$2"
  run_as_user "$user" pipx list --json | jq -e --arg id "$id" '.venvs[$id] != null' >/dev/null
}
