#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P); export PROJECT_ROOT
source "$PROJECT_ROOT/config/load.sh"; load_offsec_config "$PROJECT_ROOT"
for lib in logging common catalog; do
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/lib/$lib.sh"
done
trap cleanup_common EXIT
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
require_root; acquire_lock /run/lock/debian-offsec-bootstrap.lock
run install -d -m 0750 "$OFFSEC_LOG_ROOT"
[[ "$DRY_RUN" == false ]] && start_logging "$OFFSEC_LOG_ROOT/uninstall-$(date -u +%Y%m%dT%H%M%SZ).log" "$OFFSEC_LOG_ROOT/events.jsonl" uninstall_start
remove_tool() {
  local id="$1" method executables exe user package
  method=$(catalog_tool_field "$id" 4); package=$(catalog_tool_field "$id" 5); executables=$(catalog_tool_field "$id" 6)
  [[ -n "$method" ]] || { record_failure "unknown tool:$id" true; return; }
  case "$method" in
    pipx) user=$(invoking_user); run_as_user "$user" pipx uninstall "$package" || true ;;
    go|cargo|github)
      IFS=',' read -r -a exe_list <<< "$executables"
      for exe in "${exe_list[@]}"; do
        [[ -L "/usr/local/bin/$exe" ]] && run rm -f -- "/usr/local/bin/$exe"
        [[ "$method" == go && -f "$OFFSEC_INSTALL_ROOT/go/bin/$exe" ]] && run rm -f -- "$OFFSEC_INSTALL_ROOT/go/bin/$exe"
        [[ "$method" == cargo && -f "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe" ]] && run rm -f -- "$OFFSEC_INSTALL_ROOT/cargo/bin/$exe"
      done
      [[ -d "$OFFSEC_INSTALL_ROOT/tools/$id" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/tools/$id" "$OFFSEC_INSTALL_ROOT" ;;
    apt) record_skip "apt:$package is shared system state and was not removed" ;;
    *) record_skip "$method:$id requires documented manual removal" ;;
  esac
}
if [[ -n "$TOOL" ]]; then remove_tool "$TOOL"; elif [[ -n "$CATEGORY" ]]; then while IFS=$'\t' read -r id _; do remove_tool "$id"; done < <(awk -F '\t' -v c="$CATEGORY" '$3==c' "$PROJECT_ROOT/manifests/tool-catalog.tsv"); else
  while IFS=$'\t' read -r id _; do [[ "$id" == id ]] || remove_tool "$id"; done < "$PROJECT_ROOT/manifests/tool-catalog.tsv"
  for helper in offsec-tools offsec-status offsec-update offsec-wordlists offsec-bloodhound offsec-burp offsec-project-new; do [[ -e "/usr/local/bin/$helper" ]] && run rm -f -- "/usr/local/bin/$helper"; done
  [[ -d "$OFFSEC_INSTALL_ROOT/go" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/go" "$OFFSEC_INSTALL_ROOT"
  [[ -d "$OFFSEC_INSTALL_ROOT/cargo" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/cargo" "$OFFSEC_INSTALL_ROOT"
  [[ -d "$OFFSEC_INSTALL_ROOT/tools" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/tools" "$OFFSEC_INSTALL_ROOT"
  [[ -d "$OFFSEC_INSTALL_ROOT" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/bootstrap" "$OFFSEC_INSTALL_ROOT"
  [[ "$PURGE" == true ]] && { [[ -d "$OFFSEC_INSTALL_ROOT/resources" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/resources" "$OFFSEC_INSTALL_ROOT"; [[ -d "$OFFSEC_INSTALL_ROOT/stacks" ]] && safe_remove_tree "$OFFSEC_INSTALL_ROOT/stacks" "$OFFSEC_INSTALL_ROOT"; }
fi
[[ "$PURGE" == true && -d "$OFFSEC_STATE_ROOT" ]] && safe_remove_tree "$OFFSEC_STATE_ROOT" /var/lib
print_result_summary
