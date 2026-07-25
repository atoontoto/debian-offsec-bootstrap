#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P); export PROJECT_ROOT
source "$PROJECT_ROOT/config/load.sh"; load_offsec_config "$PROJECT_ROOT"
for lib in logging common platform catalog apt pipx golang cargo github docker wordlists verification; do
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/lib/$lib.sh"
done
trap cleanup_common EXIT
APT_ONLY=false TOOLS_ONLY=false CHECK_ONLY=false SELECTED_CATEGORIES='' UPDATE_CATEGORY=''
usage() { echo 'Usage: sudo ./update.sh [--apt-only|--tools-only] [--category NAME] [--check] [--dry-run] [--non-interactive]'; }
while (($#)); do case "$1" in
  --apt-only) APT_ONLY=true; shift ;; --tools-only) TOOLS_ONLY=true; shift ;;
  --category) (($#>=2)) || die '--category requires a value'; UPDATE_CATEGORY="$2"; SELECTED_CATEGORIES="$2"; shift 2 ;;
  --check) CHECK_ONLY=true; shift ;; --dry-run) DRY_RUN=true; shift ;; --non-interactive) NON_INTERACTIVE=true; shift ;;
  --force-unsupported) FORCE_UNSUPPORTED=true; shift ;; --help|-h) usage; exit 0 ;; *) die "Unknown option: $1" ;; esac; done
[[ "$APT_ONLY" == true && "$TOOLS_ONLY" == true ]] && die '--apt-only and --tools-only are mutually exclusive.'
export SELECTED_CATEGORIES NON_INTERACTIVE FORCE_UNSUPPORTED DRY_RUN
require_root; validate_platform; acquire_lock /run/lock/debian-offsec-bootstrap.lock
run install -d -m 0750 "$OFFSEC_LOG_ROOT"
run install -d -m 0755 "$OFFSEC_STATE_ROOT"
[[ "$DRY_RUN" == false ]] && start_logging "$OFFSEC_LOG_ROOT/update-$(date -u +%Y%m%dT%H%M%SZ).log" "$OFFSEC_LOG_ROOT/events.jsonl" update_start
if [[ "$DRY_RUN" == false && "$CHECK_ONLY" == false ]]; then network_available || die 'No HTTPS connectivity to Debian or GitHub.'; fi
if [[ "$CHECK_ONLY" == true ]]; then
  apt-get -s upgrade | sed -n '/^Inst /p'
  user=$(invoking_user); run_as_user "$user" pipx list || true
  exit 0
fi
if [[ "$TOOLS_ONLY" == false ]]; then apt_safe_upgrade; fi
if [[ "$APT_ONLY" == false ]]; then
  if [[ -n "$UPDATE_CATEGORY" ]]; then
    while IFS=$'\t' read -r id _; do pipx_upgrade_tool "$id"; done < <(catalog_rows pipx "$UPDATE_CATEGORY")
  else pipx_upgrade_all; fi
  while IFS=$'\t' read -r id _; do go_install_tool "$id"; done < <(catalog_rows go "${UPDATE_CATEGORY:-}")
  while IFS=$'\t' read -r id _; do cargo_install_tool "$id"; done < <(catalog_rows cargo "${UPDATE_CATEGORY:-}")
  while IFS=$'\t' read -r id _; do github_install_tool "$id"; done < <(catalog_rows github "${UPDATE_CATEGORY:-}")
  if [[ -z "$UPDATE_CATEGORY" || "$UPDATE_CATEGORY" == wordlists ]]; then [[ "$OFFSEC_INSTALL_WORDLISTS" == true ]] && install_wordlists; fi
  if [[ -z "$UPDATE_CATEGORY" || "$UPDATE_CATEGORY" == containers || "$UPDATE_CATEGORY" == ad ]]; then docker_pull_stacks; fi
fi
write_inventory
print_result_summary
[[ -e /var/run/reboot-required ]] && log_warn 'A reboot is required.' || log_info 'No reboot marker is present.'
command -v needrestart >/dev/null && needrestart -b 2>/dev/null || true
