#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P); export PROJECT_ROOT
source "$PROJECT_ROOT/config/load.sh"; load_offsec_config "$PROJECT_ROOT"
for lib in logging common catalog pipx docker verification; do
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/lib/$lib.sh"
done
trap cleanup_common EXIT
VERIFY_CATEGORY='' QUICK=false JSON=false
usage() { echo 'Usage: ./verify.sh [--profile core|standard|full] [--category NAME] [--json] [--quick]'; }
while (($#)); do case "$1" in
  --profile) (($#>=2)) || die '--profile requires a value'; OFFSEC_PROFILE="$2"; shift 2 ;;
  --category) (($#>=2)) || die '--category requires a value'; VERIFY_CATEGORY="$2"; shift 2 ;;
  --json) JSON=true; shift ;; --quick) QUICK=true; shift ;; --help|-h) usage; exit 0 ;; *) die "Unknown option: $1" ;; esac; done
[[ "$OFFSEC_PROFILE" =~ ^(core|standard|full)$ ]] || die 'Invalid profile.'
if [[ "$JSON" == true ]]; then
  new_temp_dir tmp_dir
  # shellcheck disable=SC2154  # assigned by validated pass-by-name helper
  tmp="$tmp_dir/inventory.json"
  inventory_args=(--catalog "$PROJECT_ROOT/manifests/tool-catalog.tsv" --profile "$OFFSEC_PROFILE" --output "$tmp" --owner "$(id -un)")
  [[ -n "$VERIFY_CATEGORY" ]] && inventory_args+=(--category "$VERIFY_CATEGORY")
  python3 "$PROJECT_ROOT/scripts/build-inventory.py" "${inventory_args[@]}"
  cat "$tmp"; exit 0
fi
verify_manifests
verify_expected_commands
if [[ "$QUICK" == false ]]; then
  pipx_verify || { log_warn 'pipx environment check failed'; ((VERIFY_WARNINGS+=1)); }
  docker_verify_stacks || ((VERIFY_WARNINGS+=1))
  verify_symlinks; verify_owned_paths
  [[ $(id -u) -eq 0 ]] && write_inventory || log_warn 'Run as root to refresh the system inventory.'
fi
printf 'Verification complete: %d required failure(s), %d warning(s).\n' "$VERIFY_REQUIRED_FAILURES" "$VERIFY_WARNINGS"
((VERIFY_REQUIRED_FAILURES == 0))
