#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
export PROJECT_ROOT
# shellcheck source=config/load.sh
source "$PROJECT_ROOT/config/load.sh"
load_offsec_config "$PROJECT_ROOT"
for lib in logging common platform catalog apt pipx golang cargo github docker desktop wordlists manual verification; do
  # Dynamic local library names come only from this fixed literal list.
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/lib/$lib.sh"
done
source "$PROJECT_ROOT/modules/_category.sh"
trap cleanup_common EXIT
trap 'log_error "Installer failed at line $LINENO"' ERR

SELECTED_CATEGORIES=
RESUME=false

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]
  --profile core|standard|full  --categories web,network,ad
  --desktop none|xfce|gnome|kde
  --with-burp | --without-burp
  --with-bloodhound | --without-bloodhound
  --with-wordlists | --without-wordlists
  --with-wireless | --without-cloud
  --allow-docker-group          Docker group is root-equivalent
  --non-interactive  --dry-run  --resume  --force-unsupported  --help
EOF
}

normalize_categories() {
  local raw="$1" item out=()
  IFS=',' read -r -a items <<< "$raw"
  for item in "${items[@]}"; do
    case "$item" in active-directory) item=ad ;; reverse|re) item=reverse-engineering ;; password) item=passwords ;; esac
    [[ "$item" =~ ^(base|network|web|ad|passwords|exploitation|cloud|wireless|reverse-engineering|forensics|osint|containers)$ ]] || die "Unknown category: $item"
    out+=("$item")
  done
  (IFS=,; echo "${out[*]}")
}

while (($#)); do
  case "$1" in
    --profile) (($# >= 2)) || die '--profile requires a value'; OFFSEC_PROFILE="$2"; shift 2 ;;
    --categories) (($# >= 2)) || die '--categories requires a value'; SELECTED_CATEGORIES=$(normalize_categories "$2"); shift 2 ;;
    --desktop) (($# >= 2)) || die '--desktop requires a value'; OFFSEC_DESKTOP="$2"; shift 2 ;;
    --with-burp) OFFSEC_INSTALL_BURP=true; shift ;; --without-burp) OFFSEC_INSTALL_BURP=false; shift ;;
    --with-bloodhound) OFFSEC_INSTALL_BLOODHOUND=true; shift ;; --without-bloodhound) OFFSEC_INSTALL_BLOODHOUND=false; shift ;;
    --with-wordlists) OFFSEC_INSTALL_WORDLISTS=true; shift ;; --without-wordlists) OFFSEC_INSTALL_WORDLISTS=false; shift ;;
    --with-wireless) OFFSEC_INSTALL_WIRELESS=true; shift ;; --without-wireless) OFFSEC_INSTALL_WIRELESS=false; shift ;;
    --with-cloud) OFFSEC_INSTALL_CLOUD=true; shift ;; --without-cloud) OFFSEC_INSTALL_CLOUD=false; shift ;;
    --allow-docker-group) OFFSEC_ALLOW_DOCKER_GROUP=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;; --dry-run) DRY_RUN=true; shift ;;
    --resume) RESUME=true; shift ;; --force-unsupported) FORCE_UNSUPPORTED=true; shift ;;
    --help|-h) usage; exit 0 ;; *) die "Unknown option: $1" ;;
  esac
done

[[ "$OFFSEC_PROFILE" =~ ^(core|standard|full)$ ]] || die "Invalid profile: $OFFSEC_PROFILE"
[[ "$OFFSEC_DESKTOP" =~ ^(none|xfce|gnome|kde)$ ]] || die "Invalid desktop: $OFFSEC_DESKTOP"
for value in "$OFFSEC_INSTALL_BURP" "$OFFSEC_INSTALL_BLOODHOUND" "$OFFSEC_INSTALL_WORDLISTS" "$OFFSEC_INSTALL_WIRELESS" "$OFFSEC_INSTALL_CLOUD" "$OFFSEC_ALLOW_DOCKER_GROUP"; do bool_value "$value"; done

if [[ -z "$SELECTED_CATEGORIES" ]]; then
  case "$OFFSEC_PROFILE" in
    core) SELECTED_CATEGORIES=base,network,web,ad,passwords,exploitation,reverse-engineering ;;
    *) SELECTED_CATEGORIES=base,network,web,ad,passwords,exploitation,cloud,reverse-engineering,forensics,osint,containers ;;
  esac
  [[ "$OFFSEC_INSTALL_WIRELESS" == true ]] && SELECTED_CATEGORIES+=,wireless
fi
export SELECTED_CATEGORIES OFFSEC_PROFILE
export FORCE_UNSUPPORTED NON_INTERACTIVE DRY_RUN
[[ "$RESUME" == true ]] && log_info 'Resume requested; idempotent channel operations will reuse installed state.'

require_root
validate_platform
check_disk_space
acquire_lock /run/lock/debian-offsec-bootstrap.lock
run install -d -m 0750 "$OFFSEC_LOG_ROOT"
run install -d -m 0755 "$OFFSEC_STATE_ROOT" "$OFFSEC_INSTALL_ROOT"
[[ "$DRY_RUN" == false ]] && start_logging "$OFFSEC_LOG_ROOT/install-$(date -u +%Y%m%dT%H%M%SZ).log" "$OFFSEC_LOG_ROOT/events.jsonl" install_start

if [[ ! -e "$OFFSEC_STATE_ROOT/authorized-use-acknowledged" ]]; then
  cat <<'NOTICE'
AUTHORIZED USE ONLY
This toolkit is for systems you own or are explicitly authorized to assess.
You are responsible for scope, consent, data handling, and applicable law.
NOTICE
  confirm 'Continue with the authorized-use terms?' || die 'Authorization notice was not accepted.'
  [[ "$DRY_RUN" == true ]] || { date -u +%FT%TZ > "$OFFSEC_STATE_ROOT/authorized-use-acknowledged"; chmod 0600 "$OFFSEC_STATE_ROOT/authorized-use-acknowledged"; }
fi

case "$OFFSEC_PROFILE" in core) download='1-3 GiB'; installed='3-6 GiB' ;; standard) download='5-12 GiB'; installed='15-30 GiB' ;; full) download='12-30 GiB'; installed='35-80 GiB' ;; esac
printf 'Detected: Debian %s %s (%s)\nProfile: %s\nCategories: %s\nDesktop: %s\nEstimated download: %s\nEstimated installed size: %s\nDestinations: %s, %s\nGUI: %s\nDocker: %s\n' \
  "$DETECTED_VERSION" "$DETECTED_CODENAME" "$DETECTED_ARCH" "$OFFSEC_PROFILE" "$SELECTED_CATEGORIES" "$OFFSEC_DESKTOP" "$download" "$installed" "$OFFSEC_INSTALL_ROOT" "$OFFSEC_WORDLIST_ROOT" "$([[ "$OFFSEC_DESKTOP" == none ]] && echo no || echo yes)" "$OFFSEC_INSTALL_BLOODHOUND"
[[ "$NON_INTERACTIVE" == true ]] || confirm 'Begin installation?' || exit 0

catalog_validate "$PROJECT_ROOT/manifests/tool-catalog.tsv" || die 'Catalog validation failed.'
apt_install_foundation

IFS=',' read -r -a categories <<< "$SELECTED_CATEGORIES"
for category in "${categories[@]}"; do
  module_name="$category"; [[ "$category" == ad ]] && module_name=active-directory
  # shellcheck disable=SC1090
  source "$PROJECT_ROOT/modules/$module_name.sh"
  # Defined by the validated module sourced immediately above.
  # shellcheck disable=SC2218
  module_install
  unset -f module_install
done

source "$PROJECT_ROOT/modules/wordlists.sh"; module_install; unset -f module_install
source "$PROJECT_ROOT/modules/desktop.sh"; module_install; unset -f module_install

for helper in offsec-tools offsec-status offsec-update offsec-wordlists offsec-bloodhound offsec-burp offsec-project-new; do run install -m 0755 "$PROJECT_ROOT/scripts/$helper" "/usr/local/bin/$helper"; done

new_temp_dir stage
# new_temp_dir validates and assigns this output variable by name.
# shellcheck disable=SC2154
tar -C "$PROJECT_ROOT" --exclude='./config/local.conf' --exclude='./.git' -cf "$stage/project.tar" .
run install -d -m 0755 "$OFFSEC_INSTALL_ROOT/bootstrap"
if [[ "$DRY_RUN" == false ]]; then tar -xf "$stage/project.tar" -C "$OFFSEC_INSTALL_ROOT/bootstrap"; fi
run chown -R root:root "$OFFSEC_INSTALL_ROOT/bootstrap"
write_inventory
print_result_summary
du -sh "$OFFSEC_INSTALL_ROOT" 2>/dev/null || true
printf 'Verification: sudo %s/verify.sh --profile %s\nWordlists: %s\nLogs: %s\nInventory: %s/inventory.json\nBloodHound: offsec-bloodhound start\nBurp: offsec-burp\n' "$PROJECT_ROOT" "$OFFSEC_PROFILE" "$OFFSEC_WORDLIST_ROOT" "$OFFSEC_LOG_ROOT" "$OFFSEC_STATE_ROOT"
printf 'Reminder: use these tools only within explicit authorization and scope.\n'
((${#OFFSEC_FAILED_REQUIRED[@]} == 0))
