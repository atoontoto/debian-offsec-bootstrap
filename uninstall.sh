#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P); export PROJECT_ROOT
source "$PROJECT_ROOT/config/load.sh"; load_offsec_config "$PROJECT_ROOT"
for lib in logging common catalog pipx docker desktop verification; do
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/lib/$lib.sh"
done
trap cleanup_common EXIT
trap 'report_entrypoint_error "$?" "$LINENO" uninstaller' ERR
TOOL='' CATEGORY='' ALL=false PURGE=false
usage() { echo 'Usage: sudo ./uninstall.sh (--tool TOOL|--category CATEGORY|--all) [--purge-data] [--dry-run]'; }
while (($#)); do case "$1" in
  --tool) (($#>=2)) || die '--tool requires a value'; TOOL="$2"; shift 2 ;; --category) (($#>=2)) || die '--category requires a value'; CATEGORY="$2"; shift 2 ;;
  --all) ALL=true; shift ;; --purge-data) PURGE=true; shift ;; --dry-run) DRY_RUN=true; shift ;; --help|-h) usage; exit 0 ;; *) die "Unknown option: $1" ;; esac; done
choice_count=0
[[ -n "$TOOL" ]] && ((choice_count+=1))
[[ -n "$CATEGORY" ]] && ((choice_count+=1))
[[ "$ALL" == true ]] && ((choice_count+=1))
((choice_count == 1)) || die 'Choose exactly one of --tool, --category, or --all.'
[[ "$OFFSEC_PROFILE" =~ ^(core|standard|full)$ ]] || die "Invalid profile: $OFFSEC_PROFILE"
validate_runtime_config
if [[ -n "$TOOL" ]]; then [[ -n $(catalog_tool_field "$TOOL" 1) ]] || die "Unknown tool: $TOOL"; fi
if [[ -n "$CATEGORY" ]]; then valid_category "$CATEGORY" || die "Unknown category: $CATEGORY"; fi
require_root; acquire_lock /run/lock/debian-offsec-bootstrap.lock
run install -d -m 0750 "$OFFSEC_LOG_ROOT"
if [[ "$DRY_RUN" == false ]]; then start_logging "$OFFSEC_LOG_ROOT/uninstall-$(date -u +%Y%m%dT%H%M%SZ).log" "$OFFSEC_LOG_ROOT/events.jsonl" uninstall_start; fi
remove_project_helper() {
  local helper="$1" path="/usr/local/bin/$1" installed_source="$OFFSEC_INSTALL_ROOT/bootstrap/scripts/$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ -L "$path" ]]; then
    remove_managed_symlink "$path" "$OFFSEC_INSTALL_ROOT"
  elif [[ -f "$path" ]] && { { [[ -f "$installed_source" ]] && cmp -s -- "$path" "$installed_source"; } || cmp -s -- "$path" "$PROJECT_ROOT/scripts/$helper"; }; then
    run rm -f -- "$path"
  else
    record_skip "$path was modified and was not removed"
  fi
}
remove_tool() {
  local id="$1" method executables exe user package stack resource_name resource_url resource_link resource_target burp_marker rockyou_marker
  method=$(catalog_tool_field "$id" 4); package=$(catalog_tool_field "$id" 5); executables=$(catalog_tool_field "$id" 6)
  [[ -n "$method" ]] || { record_failure "unknown tool:$id" true; return; }
  case "$method" in
    pipx)
      user=$(invoking_user)
      if [[ "$DRY_RUN" == true ]]; then run_as_user "$user" pipx uninstall "$id"
      elif pipx_environment_exists "$user" "$id"; then run_as_user "$user" pipx uninstall "$id" || record_failure "pipx:$id uninstall" true
      else record_skip "pipx:$id is not installed"; fi
      ;;
    go|cargo|github)
      IFS=',' read -r -a exe_list <<< "$executables"
      for exe in "${exe_list[@]}"; do
        if [[ -L "/usr/local/bin/$exe" ]]; then remove_managed_symlink "/usr/local/bin/$exe" "$OFFSEC_INSTALL_ROOT"; fi
        [[ "$method" == go && -f "$OFFSEC_INSTALL_ROOT/go/bin/$exe" ]] && run rm -f -- "$OFFSEC_INSTALL_ROOT/go/bin/$exe"
        [[ "$method" == cargo && -f "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe" ]] && run rm -f -- "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe"
      done
      [[ -d "$OFFSEC_INSTALL_ROOT/tools/$id" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/tools/$id" "$OFFSEC_INSTALL_ROOT" ;;
    apt) record_skip "apt:$package is shared system state and was not removed" ;;
    docker)
      if [[ "$id" == bloodhound-ce && "$PURGE" == true ]]; then
        stack="$OFFSEC_INSTALL_ROOT/stacks/bloodhound"
        if [[ -f "$stack/compose.yml" ]]; then
          run docker_compose --project-directory "$stack" --env-file "$stack/.env" -f "$stack/compose.yml" down --remove-orphans -v || { record_failure 'docker:bloodhound-ce volume removal' true; return; }
        fi
        if [[ -d "$stack" ]]; then safe_remove_tree "$stack" "$OFFSEC_INSTALL_ROOT"; fi
      else record_skip "docker:$id data preserved (use --purge-data to remove managed stack data)"; fi
      ;;
    manual)
      if [[ "$id" == burpsuite ]]; then
        burp_marker=/opt/burpsuite-community/.debian-offsec-bootstrap-owned
        if [[ -f "$burp_marker" && ! -L "$burp_marker" && $(stat -c '%u' "$burp_marker") == 0 && $(< "$burp_marker") == debian-offsec-bootstrap ]]; then
          if [[ -L /usr/local/bin/burpsuite ]]; then remove_managed_symlink /usr/local/bin/burpsuite /opt; fi
          safe_remove_tree /opt/burpsuite-community /opt
        else record_skip 'manual:burpsuite has no valid project ownership marker and was not removed'; fi
      elif [[ "$id" == seclists || "$id" == payloadsallthethings ]]; then
        if [[ "$PURGE" == true ]]; then
          IFS=$'\t' read -r resource_name resource_url _ resource_link < <(awk -F '\t' -v wanted="$id" 'tolower($1) == wanted { print; exit }' "$PROJECT_ROOT/manifests/git-resources.tsv")
          resource_target="$OFFSEC_INSTALL_ROOT/resources/$resource_name"
          if [[ -d "$resource_target/.git" && $(env GIT_TERMINAL_PROMPT=0 git -C "$resource_target" remote get-url origin 2>/dev/null) == "$resource_url" ]]; then
            if [[ -L "$OFFSEC_WORDLIST_ROOT/$resource_link" ]]; then remove_managed_symlink "$OFFSEC_WORDLIST_ROOT/$resource_link" "$OFFSEC_INSTALL_ROOT"; fi
            safe_remove_tree "$resource_target" "$OFFSEC_INSTALL_ROOT"
          else record_skip "manual:$id has no matching managed Git origin and was not removed"; fi
        else record_skip "manual:$id data preserved (use --purge-data to remove it)"; fi
      elif [[ "$id" == rockyou ]]; then
        rockyou_marker="$OFFSEC_STATE_ROOT/rockyou-decompressed"
        if [[ "$PURGE" == true && -f "$rockyou_marker" && ! -L "$rockyou_marker" && $(stat -c '%u' "$rockyou_marker") == 0 && $(< "$rockyou_marker") == "$OFFSEC_WORDLIST_ROOT/rockyou.txt" ]]; then
          if [[ -f "$OFFSEC_WORDLIST_ROOT/rockyou.txt" && ! -L "$OFFSEC_WORDLIST_ROOT/rockyou.txt" ]]; then run rm -f -- "$OFFSEC_WORDLIST_ROOT/rockyou.txt"; fi
          run rm -f -- "$rockyou_marker"
        else record_skip 'manual:rockyou was not removed without a matching ownership marker and --purge-data'; fi
      else record_skip "manual:$id was not automatically installed and was not removed"; fi
      ;;
    *) record_skip "$method:$id requires documented manual removal" ;;
  esac
  return 0
}
if [[ -n "$TOOL" ]]; then remove_tool "$TOOL"; elif [[ -n "$CATEGORY" ]]; then while IFS=$'\t' read -r id _; do remove_tool "$id"; done < <(awk -F '\t' -v c="$CATEGORY" '$3==c' "$PROJECT_ROOT/manifests/tool-catalog.tsv"); else
  while IFS=$'\t' read -r id _; do [[ "$id" == id ]] || remove_tool "$id"; done < "$PROJECT_ROOT/manifests/tool-catalog.tsv"
  for helper in offsec-tools offsec-status offsec-update offsec-wordlists offsec-bloodhound offsec-burp offsec-project-new; do remove_project_helper "$helper"; done
  while IFS=$'\t' read -r name _ _ link || [[ -n "$name" ]]; do
    [[ "$name" == id || -z "$name" || "$name" == \#* ]] && continue
    if [[ -L "$OFFSEC_WORDLIST_ROOT/$link" ]]; then remove_managed_symlink "$OFFSEC_WORDLIST_ROOT/$link" "$OFFSEC_INSTALL_ROOT"; fi
  done < "$PROJECT_ROOT/manifests/git-resources.tsv"
  for desktop_file in offsec-bloodhound.desktop offsec-burp.desktop; do
    desktop_target="/usr/share/applications/$desktop_file"
    if [[ -f "$desktop_target" && ! -L "$desktop_target" ]]; then
      if cmp -s -- "$desktop_target" "$PROJECT_ROOT/desktop/$desktop_file" || { [[ -f "$OFFSEC_INSTALL_ROOT/bootstrap/desktop/$desktop_file" ]] && cmp -s -- "$desktop_target" "$OFFSEC_INSTALL_ROOT/bootstrap/desktop/$desktop_file"; }; then
        run rm -f -- "$desktop_target"
      else record_skip "$desktop_target was modified and was not removed"; fi
    fi
  done
  [[ -d "$OFFSEC_INSTALL_ROOT/go" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/go" "$OFFSEC_INSTALL_ROOT"
  [[ -d "$OFFSEC_INSTALL_ROOT/cargo" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/cargo" "$OFFSEC_INSTALL_ROOT"
  [[ -d "$OFFSEC_INSTALL_ROOT/tools" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/tools" "$OFFSEC_INSTALL_ROOT"
  [[ -d "$OFFSEC_INSTALL_ROOT" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/bootstrap" "$OFFSEC_INSTALL_ROOT"
  if [[ "$PURGE" == true ]]; then
    if [[ -d "$OFFSEC_INSTALL_ROOT/resources" ]]; then run rmdir --ignore-fail-on-non-empty -- "$OFFSEC_INSTALL_ROOT/resources"; fi
    if [[ -d "$OFFSEC_INSTALL_ROOT/stacks" ]]; then run rmdir --ignore-fail-on-non-empty -- "$OFFSEC_INSTALL_ROOT/stacks"; fi
  fi
  :
fi
if [[ "$CATEGORY" == desktop ]]; then
  for desktop_file in offsec-bloodhound.desktop offsec-burp.desktop; do
    desktop_target="/usr/share/applications/$desktop_file"
    if [[ -f "$desktop_target" && ! -L "$desktop_target" ]]; then
      if cmp -s -- "$desktop_target" "$PROJECT_ROOT/desktop/$desktop_file" || { [[ -f "$OFFSEC_INSTALL_ROOT/bootstrap/desktop/$desktop_file" ]] && cmp -s -- "$desktop_target" "$OFFSEC_INSTALL_ROOT/bootstrap/desktop/$desktop_file"; }; then
        run rm -f -- "$desktop_target"
      else record_skip "$desktop_target was modified and was not removed"; fi
    fi
  done
fi
if [[ "$ALL" == true || "$CATEGORY" == desktop ]]; then desktop_remove_shell_integration; fi
if [[ "$PURGE" == true && "$ALL" == true && -d "$OFFSEC_STATE_ROOT" ]]; then safe_remove_tree "$OFFSEC_STATE_ROOT" "$(dirname -- "$OFFSEC_STATE_ROOT")"; fi
if [[ "$PURGE" == false || "$ALL" == false ]]; then write_inventory; fi
print_result_summary
if ((${#OFFSEC_FAILED_REQUIRED[@]})); then exit 1; fi
exit 0
