#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# github-tools.tsv accepts the original seven-column rows and component rows:
# tool-id, component-id, owner/repo, tag, architecture, asset-regex,
# checksum-url-template, archive-executable:installed-command mappings,
# strip-components, verification-arguments.
github_manifest_rows() { awk -F '\t' -v id="$1" '$1==id {print}' "$PROJECT_ROOT/manifests/github-tools.tsv"; }

github_parse_manifest_row() {
  local row="$1" fields=()
  IFS=$'\t' read -r -a fields <<< "$row"
  case ${#fields[@]} in
    7)
      GH_TOOL=${fields[0]}; GH_COMPONENT=${fields[0]}; GH_REPO=${fields[1]}; GH_TAG=${fields[2]}
      GH_ARCH=amd64; GH_ASSET_REGEX=${fields[3]}; GH_CHECKSUM_URL=${fields[4]}
      GH_MAPPINGS=${fields[5]}; GH_STRIP=${fields[6]}; GH_VERIFY_ARGS=
      ;;
    10)
      GH_TOOL=${fields[0]}; GH_COMPONENT=${fields[1]}; GH_REPO=${fields[2]}; GH_TAG=${fields[3]}
      GH_ARCH=${fields[4]}; GH_ASSET_REGEX=${fields[5]}; GH_CHECKSUM_URL=${fields[6]}
      GH_MAPPINGS=${fields[7]}; GH_STRIP=${fields[8]}; GH_VERIFY_ARGS=${fields[9]}
      ;;
    *) return 1 ;;
  esac
}

github_select_asset() {
  local regex="$1" python_cmd
  python_cmd=$(python_runtime) || return 1
  "$python_cmd" "$PROJECT_ROOT/scripts/select-github-asset.py" "$regex"
}

github_asset_metadata() {
  local repo="$1" tag="$2" regex="$3" api
  api="https://api.github.com/repos/$repo/releases/tags/$tag"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$api" | github_select_asset "$regex"
}

github_checksum_for_asset() {
  local checksum_file="$1" asset="$2" line digest filename count=0 selected=
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^([0-9A-Fa-f]{64})[[:space:]]+[*]?([^[:space:]]+)$ ]]; then
      digest=${BASH_REMATCH[1],,}; filename=${BASH_REMATCH[2]}
      if [[ "$filename" == "$asset" ]]; then count=$((count+1)); selected=$digest; fi
    elif [[ "$line" == *"$asset"* ]]; then
      return 2
    fi
  done < "$checksum_file"
  ((count == 1)) || return 1
  printf '%s\n' "$selected"
}

github_mapping_parts() {
  local mapping="$1"
  if [[ "$mapping" == *:* ]]; then
    GH_ARCHIVE_EXECUTABLE=${mapping%%:*}; GH_INSTALLED_COMMAND=${mapping#*:}
  else
    GH_ARCHIVE_EXECUTABLE=$mapping; GH_INSTALLED_COMMAND=$mapping
  fi
  [[ "$GH_ARCHIVE_EXECUTABLE" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || return 1
  [[ "$GH_INSTALLED_COMMAND" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || return 1
}

github_component_root() {
  local root="$1" levels="$2" level entries=()
  [[ "$levels" =~ ^[0-9]+$ ]] || return 1
  for ((level=0; level<levels; level++)); do
    mapfile -d '' -t entries < <(find "$root" -mindepth 1 -maxdepth 1 -print0)
    ((${#entries[@]} == 1)) && [[ -d ${entries[0]} && ! -L ${entries[0]} ]] || return 1
    root=${entries[0]}
  done
  printf '%s\n' "$root"
}

github_validate_managed_link() {
  local link="$1" allowed_root="$2" resolved root_resolved
  [[ -e "$link" || -L "$link" ]] || return 0
  [[ -L "$link" ]] || return 1
  resolved=$(realpath -m -- "$link") || return 1
  root_resolved=$(realpath -m -- "$allowed_root") || return 1
  path_is_within "$resolved" "$root_resolved"
}

github_atomic_link() {
  local target="$1" link="$2" allowed_root="$3" parent temporary
  github_validate_managed_link "$link" "$allowed_root" || return 1
  parent=$(dirname -- "$link")
  temporary="$parent/.${link##*/}.offsec.$$"
  [[ ! -e "$temporary" && ! -L "$temporary" ]] || return 1
  ln -s -- "$target" "$temporary" || return 1
  if ! mv -Tf -- "$temporary" "$link"; then rm -f -- "$temporary"; return 1; fi
}

github_restore_link() {
  local link="$1" previous="$2"
  rm -f -- "$link"
  [[ -n "$previous" ]] && ln -s -- "$previous" "$link"
}

github_install_tool() {
  local id="$1" required=false arch row tmp tool_stage component_root metadata name url archive sumfile expected
  local dest backup current old_current='' state_tmp state_file source_url checksum_sources='' component_summary=''
  local command_root=${OFFSEC_COMMAND_ROOT:-/usr/local/bin}
  local mapping found verify_output install_failed=false activated=false destination_had_backup=false
  local -a rows=() mappings=() found_files=() verify_args=() command_names=() command_sources=() old_command_links=()
  local -A checksum_files=() seen_components=() seen_commands=() seen_sources=()
  catalog_tool_required "$id" && required=true
  arch=${DETECTED_ARCH:-$(dpkg --print-architecture 2>/dev/null || true)}
  mapfile -t rows < <(github_manifest_rows "$id")
  ((${#rows[@]})) || { record_failure "github:$id (missing manifest entry)" "$required"; return; }

  local repo= tag=
  for row in "${rows[@]}"; do
    github_parse_manifest_row "$row" || { record_failure "github:$id (invalid manifest row)" "$required"; return; }
    [[ "$GH_ARCH" == "$arch" ]] || continue
    [[ -z "$repo" || "$repo" == "$GH_REPO" ]] || { record_failure "github:$id (component repository mismatch)" "$required"; return; }
    [[ -z "$tag" || "$tag" == "$GH_TAG" ]] || { record_failure "github:$id (component tag mismatch)" "$required"; return; }
    repo=$GH_REPO; tag=$GH_TAG
    [[ -z ${seen_components[$GH_COMPONENT]:-} ]] || { record_failure "github:$id (duplicate component $GH_COMPONENT)" "$required"; return; }
    seen_components[$GH_COMPONENT]=1
    component_summary+="${component_summary:+, }$GH_COMPONENT [$GH_MAPPINGS]"
  done
  [[ -n "$repo" ]] || { record_failure "github:$id (unsupported architecture: ${arch:-unknown})" "$required"; return; }
  if [[ "$DRY_RUN" == true ]]; then
    record_success "github:$id ($repo $tag; $component_summary; pinned checksums required)"
    return 0
  fi

  new_temp_dir tmp
  tool_stage="$tmp/tool"; install -d -m 0755 -- "$tool_stage"
  for row in "${rows[@]}"; do
    github_parse_manifest_row "$row" || return 1
    [[ "$GH_ARCH" == "$arch" ]] || continue
    [[ "$GH_CHECKSUM_URL" != - && -n "$GH_CHECKSUM_URL" ]] || { record_failure "github:$id/$GH_COMPONENT (upstream checksum not configured)" "$required"; return; }
    metadata=$(github_asset_metadata "$GH_REPO" "$GH_TAG" "$GH_ASSET_REGEX") || { record_failure "github:$id/$GH_COMPONENT release lookup (expected one asset)" "$required"; return; }
    IFS=$'\t' read -r name url <<< "$metadata"
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && "$name" =~ $GH_ASSET_REGEX ]] || { record_failure "github:$id/$GH_COMPONENT invalid release asset name" "$required"; return; }
    [[ "$url" == "https://github.com/$GH_REPO/releases/download/$GH_TAG/$name" ]] || { record_failure "github:$id/$GH_COMPONENT non-official release URL" "$required"; return; }
    archive="$tmp/$GH_COMPONENT-$name"
    download_https "$url" "$archive" || { record_failure "github:$id/$GH_COMPONENT asset download" "$required"; return; }
    GH_CHECKSUM_URL=${GH_CHECKSUM_URL//\{tag\}/$GH_TAG}; GH_CHECKSUM_URL=${GH_CHECKSUM_URL//\{asset\}/$name}
    if [[ -z ${checksum_files[$GH_CHECKSUM_URL]:-} ]]; then
      sumfile="$tmp/checksums-${#checksum_files[@]}.txt"
      download_https "$GH_CHECKSUM_URL" "$sumfile" || { record_failure "github:$id checksum download" "$required"; return; }
      checksum_files[$GH_CHECKSUM_URL]=$sumfile
      checksum_sources+="${checksum_sources:+,}$GH_CHECKSUM_URL"
    else sumfile=${checksum_files[$GH_CHECKSUM_URL]}; fi
    expected=$(github_checksum_for_asset "$sumfile" "$name") || { record_failure "github:$id/$GH_COMPONENT checksum entry" "$required"; return; }
    verify_sha256 "$archive" "$expected" || { record_failure "github:$id/$GH_COMPONENT checksum mismatch" "$required"; return; }
    component_root="$tmp/extract-$GH_COMPONENT"
    extract_archive "$archive" "$component_root" || { record_failure "github:$id/$GH_COMPONENT unsafe archive" "$required"; return; }
    component_root=$(github_component_root "$component_root" "$GH_STRIP") || { record_failure "github:$id/$GH_COMPONENT invalid strip-components layout" "$required"; return; }
    IFS=',' read -r -a mappings <<< "$GH_MAPPINGS"
    for mapping in "${mappings[@]}"; do
      github_mapping_parts "$mapping" || { record_failure "github:$id/$GH_COMPONENT invalid executable mapping" "$required"; return; }
      [[ -z ${seen_commands[$GH_INSTALLED_COMMAND]:-} && -z ${seen_sources[$GH_ARCHIVE_EXECUTABLE]:-} ]] || { record_failure "github:$id duplicate executable mapping" "$required"; return; }
      mapfile -d '' -t found_files < <(find "$component_root" -type f -name "$GH_ARCHIVE_EXECUTABLE" -print0)
      ((${#found_files[@]} == 1)) || { record_failure "github:$id/$GH_COMPONENT expected exactly one $GH_ARCHIVE_EXECUTABLE" "$required"; return; }
      found=${found_files[0]}
      [[ -f "$found" && ! -L "$found" ]] || { record_failure "github:$id/$GH_COMPONENT executable is not a regular file" "$required"; return; }
      chmod 0755 -- "$found"
      install -m 0755 -- "$found" "$tool_stage/$GH_ARCHIVE_EXECUTABLE"
      seen_commands[$GH_INSTALLED_COMMAND]=1; seen_sources[$GH_ARCHIVE_EXECUTABLE]=1
      command_names+=("$GH_INSTALLED_COMMAND"); command_sources+=("$GH_ARCHIVE_EXECUTABLE")
      if [[ -n "$GH_VERIFY_ARGS" && "$GH_VERIFY_ARGS" != - ]]; then
        IFS=' ' read -r -a verify_args <<< "$GH_VERIFY_ARGS"
        verify_output=$("$tool_stage/$GH_ARCHIVE_EXECUTABLE" "${verify_args[@]}" 2>&1) || { record_failure "github:$id/$GH_COMPONENT staged verification" "$required"; return; }
        [[ -n "$verify_output" ]] || { record_failure "github:$id/$GH_COMPONENT empty verification output" "$required"; return; }
      fi
    done
  done

  dest="$OFFSEC_INSTALL_ROOT/tools/$id/$tag"; backup="$OFFSEC_INSTALL_ROOT/tools/$id/.previous-$tag"; current="$OFFSEC_INSTALL_ROOT/tools/$id/current"
  ensure_managed_directory "$OFFSEC_INSTALL_ROOT/tools/$id" "$OFFSEC_INSTALL_ROOT"
  [[ ! -L "$dest" && ( ! -e "$dest" || -d "$dest" ) && ! -e "$backup" ]] || { record_failure "github:$id unsafe activation state" "$required"; return; }
  github_validate_managed_link "$current" "$OFFSEC_INSTALL_ROOT" || { record_failure "github:$id unsafe current link" "$required"; return; }
  [[ -L "$current" ]] && old_current=$(readlink -- "$current")
  local index link
  for ((index=0; index<${#command_names[@]}; index++)); do
    link="$command_root/${command_names[$index]}"
    github_validate_managed_link "$link" "$OFFSEC_INSTALL_ROOT" || { record_failure "github:$id refuses unmanaged command $link" "$required"; return; }
    if [[ -L "$link" ]]; then old_command_links+=("$(readlink -- "$link")"); else old_command_links+=(""); fi
  done
  chown -R root:root -- "$tool_stage"
  if [[ -d "$dest" ]]; then mv -- "$dest" "$backup"; destination_had_backup=true; fi
  if ! mv -- "$tool_stage" "$dest"; then
    [[ "$destination_had_backup" == true ]] && mv -- "$backup" "$dest"
    record_failure "github:$id version activation" "$required"; return
  fi
  if ! github_atomic_link "$dest" "$current" "$OFFSEC_INSTALL_ROOT"; then install_failed=true
  else activated=true; fi
  if [[ "$install_failed" == false ]]; then
    for ((index=0; index<${#command_names[@]}; index++)); do
      link="$command_root/${command_names[$index]}"
      if ! github_atomic_link "$current/${command_sources[$index]}" "$link" "$OFFSEC_INSTALL_ROOT"; then install_failed=true; break; fi
    done
  fi
  if [[ "$install_failed" == false ]]; then
    for row in "${rows[@]}"; do
      github_parse_manifest_row "$row" || continue
      [[ "$GH_ARCH" == "$arch" ]] || continue
      [[ -n "$GH_VERIFY_ARGS" && "$GH_VERIFY_ARGS" != - ]] || continue
      IFS=',' read -r -a mappings <<< "$GH_MAPPINGS"
      for mapping in "${mappings[@]}"; do
        github_mapping_parts "$mapping" || continue
        IFS=' ' read -r -a verify_args <<< "$GH_VERIFY_ARGS"
        verify_output=$("$command_root/$GH_INSTALLED_COMMAND" "${verify_args[@]}" 2>&1) || { install_failed=true; break 2; }
        [[ -n "$verify_output" ]] || { install_failed=true; break 2; }
      done
    done
  fi
  if [[ "$install_failed" == true ]]; then
    for ((index=0; index<${#command_names[@]}; index++)); do github_restore_link "$command_root/${command_names[$index]}" "${old_command_links[$index]}"; done
    [[ "$activated" == true ]] && github_restore_link "$current" "$old_current"
    safe_remove_tree "$dest" "$OFFSEC_INSTALL_ROOT"
    [[ "$destination_had_backup" == true ]] && mv -- "$backup" "$dest"
    record_failure "github:$id activation or verification (previous version restored)" "$required"
    return
  fi
  [[ "$destination_had_backup" == true ]] && safe_remove_tree "$backup" "$OFFSEC_INSTALL_ROOT"

  new_temp_dir state_tmp_dir
  state_tmp="$state_tmp_dir/github-installed.tsv"; state_file="$OFFSEC_STATE_ROOT/github-installed.tsv"
  [[ -f "$state_file" ]] && awk -F '\t' -v wanted="$id" '$1 != wanted' "$state_file" > "$state_tmp"
  source_url="https://github.com/$repo/releases/tag/$tag"
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$tag" "$source_url" "$checksum_sources" "$component_summary" >> "$state_tmp"
  atomic_install_file "$state_tmp" "$state_file" 0644
  record_success "github:$id ($component_summary)"
}

github_install_category() {
  local category="$1" row id
  while IFS= read -r row; do IFS=$'\t' read -r id _ <<< "$row"; github_install_tool "$id"; done < <(catalog_rows github "$category")
}
