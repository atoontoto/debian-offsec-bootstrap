#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

CATALOG_COLUMNS=17

catalog_validate() {
  local file="$1" line=0 fields id method profile
  declare -A seen=()
  while IFS=$'\t' read -r -a fields || ((${#fields[@]})); do
    ((line+=1))
    [[ ${fields[0]:-} == id ]] && continue
    [[ -z ${fields[0]:-} || ${fields[0]} == \#* ]] && continue
    ((${#fields[@]} == CATALOG_COLUMNS)) || { log_error "$file:$line expected $CATALOG_COLUMNS fields, got ${#fields[@]}"; return 1; }
    id=${fields[0]}; method=${fields[3]}; profile=${fields[15]}
    [[ "$id" =~ ^[a-z0-9][a-z0-9._+-]*$ ]] || { log_error "$file:$line invalid id: $id"; return 1; }
    [[ -z ${seen[$id]:-} ]] || { log_error "$file:$line duplicate id: $id"; return 1; }; seen[$id]=1
    [[ "$method" =~ ^(apt|pipx|go|cargo|github|docker|manual)$ ]] || { log_error "$file:$line invalid method: $method"; return 1; }
    [[ "$profile" =~ ^(core|standard|full|optional)$ ]] || { log_error "$file:$line invalid profile: $profile"; return 1; }
  done < "$file"
}

profile_includes() {
  local selected="$1" membership="$2"
  case "$selected" in core) [[ "$membership" == core ]] ;; standard) [[ "$membership" == core || "$membership" == standard ]] ;; full) [[ "$membership" != optional ]] ;; *) return 1 ;; esac
}

category_selected() {
  local category="$1"
  [[ -z ${SELECTED_CATEGORIES:-} ]] && return 0
  [[ ",${SELECTED_CATEGORIES}," == *",${category},"* ]]
}

catalog_rows() {
  local method_filter="${1:-}" category_filter="${2:-}" fields
  while IFS=$'\t' read -r -a fields || ((${#fields[@]})); do
    [[ ${fields[0]:-} == id || -z ${fields[0]:-} || ${fields[0]} == \#* ]] && continue
    [[ -z "$method_filter" || ${fields[3]} == "$method_filter" ]] || continue
    [[ -z "$category_filter" || ${fields[2]} == "$category_filter" ]] || continue
    profile_includes "$OFFSEC_PROFILE" "${fields[15]}" || continue
    category_selected "${fields[2]}" || continue
    printf '%s\n' "$(IFS=$'\t'; echo "${fields[*]}")"
  done < "$PROJECT_ROOT/manifests/tool-catalog.tsv"
}

catalog_tool_field() {
  local wanted="$1" column="$2"
  awk -F '\t' -v id="$wanted" -v col="$column" '$1==id {print $col; exit}' "$PROJECT_ROOT/manifests/tool-catalog.tsv"
}
