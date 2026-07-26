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
trap 'report_entrypoint_error "$?" "$LINENO" installer' ERR

SELECTED_CATEGORIES=
RESUME=false
AUTHORIZED_USE_ACCEPTED=false

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [options]
  --profile core|standard|full  --categories web,network,ad
  --desktop none|xfce|gnome|kde
  --with-burp | --without-burp
  --with-bloodhound | --without-bloodhound
  --with-wordlists | --without-wordlists
  --with-wireless | --without-wireless
  --with-cloud | --without-cloud
  --allow-docker-group          Docker group is root-equivalent
  --accept-authorized-use       Required for a fresh non-interactive install
  --non-interactive  --dry-run  --resume  --force-unsupported  --help
EOF
}

normalize_categories() {
  local raw="$1" item out=() items=()
  declare -A seen=()
  [[ -n "$raw" ]] || die 'Categories must not be empty.'
  IFS=',' read -r -a items <<< "$raw"
  for item in "${items[@]}"; do
    case "$item" in active-directory) item=ad ;; reverse|re) item=reverse-engineering ;; password) item=passwords ;; esac
    [[ "$item" =~ ^(base|network|web|ad|passwords|exploitation|cloud|wireless|reverse-engineering|forensics|osint|containers)$ ]] || die "Unknown category: $item"
    [[ -z ${seen[$item]:-} ]] || continue
    seen[$item]=1
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
    --accept-authorized-use) AUTHORIZED_USE_ACCEPTED=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;; --dry-run) DRY_RUN=true; shift ;;
    --resume) RESUME=true; shift ;; --force-unsupported) FORCE_UNSUPPORTED=true; shift ;;
    --help|-h) usage; exit 0 ;; *) die "Unknown option: $1" ;;
  esac
done

[[ "$OFFSEC_PROFILE" =~ ^(core|standard|full)$ ]] || die "Invalid profile: $OFFSEC_PROFILE"
[[ "$OFFSEC_DESKTOP" =~ ^(none|xfce|gnome|kde)$ ]] || die "Invalid desktop: $OFFSEC_DESKTOP"
validate_runtime_config

if [[ -z "$SELECTED_CATEGORIES" ]]; then
  case "$OFFSEC_PROFILE" in
    core) SELECTED_CATEGORIES=base,network,web,ad,passwords,exploitation,reverse-engineering ;;
    *) SELECTED_CATEGORIES=base,network,web,ad,passwords,exploitation,cloud,reverse-engineering,forensics,osint,containers ;;
  esac
  if [[ "$OFFSEC_INSTALL_WIRELESS" == true ]]; then SELECTED_CATEGORIES+=,wireless; fi
fi
export SELECTED_CATEGORIES OFFSEC_PROFILE OFFSEC_INSTALL_BURP OFFSEC_INSTALL_BLOODHOUND OFFSEC_INSTALL_WORDLISTS OFFSEC_INSTALL_WIRELESS OFFSEC_INSTALL_CLOUD OFFSEC_ALLOW_DOCKER_GROUP
export FORCE_UNSUPPORTED NON_INTERACTIVE DRY_RUN
[[ "$RESUME" == true ]] && log_info 'Resume requested; idempotent channel operations will reuse installed state.'

require_root
validate_platform
check_disk_space
acquire_lock /run/lock/debian-offsec-bootstrap.lock
run install -d -m 0750 "$OFFSEC_LOG_ROOT"
run install -d -m 0755 "$OFFSEC_STATE_ROOT" "$OFFSEC_INSTALL_ROOT"
if [[ "$DRY_RUN" == false ]]; then start_logging "$OFFSEC_LOG_ROOT/install-$(date -u +%Y%m%dT%H%M%SZ).log" "$OFFSEC_LOG_ROOT/events.jsonl" install_start; fi

acknowledgement="$OFFSEC_STATE_ROOT/authorized-use-acknowledged"
if [[ -e "$acknowledgement" ]]; then
  [[ -f "$acknowledgement" && ! -L "$acknowledgement" && $(stat -c '%u' "$acknowledgement") == 0 ]] || die "Unsafe authorization acknowledgement: $acknowledgement"
else
  cat <<'NOTICE'
AUTHORIZED USE ONLY
This toolkit is for systems you own or are explicitly authorized to assess.
You are responsible for scope, consent, data handling, and applicable law.
NOTICE
  if [[ "$AUTHORIZED_USE_ACCEPTED" == true ]]; then
    :
  elif [[ "$NON_INTERACTIVE" == true && "$DRY_RUN" == true ]]; then
    log_info 'Dry-run only: authorization was not persisted. Pass --accept-authorized-use for an actual non-interactive install.'
  elif [[ "$NON_INTERACTIVE" == true ]]; then
    die 'A fresh non-interactive install requires --accept-authorized-use.'
  elif ! confirm 'Continue with the authorized-use terms?'; then
    die 'Authorization notice was not accepted.'
  fi
  if [[ "$DRY_RUN" == false ]]; then
    new_temp_dir acknowledgement_stage
    # shellcheck disable=SC2154  # assigned by validated pass-by-name helper
    date -u +%FT%TZ > "$acknowledgement_stage/authorized-use-acknowledged"
    atomic_install_file "$acknowledgement_stage/authorized-use-acknowledged" "$acknowledgement" 0600
  fi
fi

case "$OFFSEC_PROFILE" in core) download='1-3 GiB'; installed='3-6 GiB' ;; standard) download='5-12 GiB'; installed='15-30 GiB' ;; full) download='12-30 GiB'; installed='35-80 GiB' ;; esac
printf 'Detected: Debian %s %s (%s)\nProfile: %s\nCategories: %s\nDesktop: %s\nEstimated download: %s\nEstimated installed size: %s\nDestinations: %s, %s\nGUI: %s\nDocker: %s\n' \
  "$DETECTED_VERSION" "$DETECTED_CODENAME" "$DETECTED_ARCH" "$OFFSEC_PROFILE" "$SELECTED_CATEGORIES" "$OFFSEC_DESKTOP" "$download" "$installed" "$OFFSEC_INSTALL_ROOT" "$OFFSEC_WORDLIST_ROOT" "$([[ "$OFFSEC_DESKTOP" == none ]] && echo no || echo yes)" "$OFFSEC_INSTALL_BLOODHOUND"
if [[ "$NON_INTERACTIVE" == false ]]; then
  if confirm 'Begin installation?'; then :; else
    prompt_status=$?
    ((prompt_status == 2)) && die 'Cannot begin an interactive installation without a controlling terminal.'
    log_info 'Installation cancelled.'
    exit 0
  fi
fi

catalog_validate "$PROJECT_ROOT/manifests/tool-catalog.tsv" || die 'Catalog validation failed.'
apt_install_foundation
if ((${#OFFSEC_FAILED_REQUIRED[@]})); then print_result_summary; die 'Required foundation installation failed; optional channels were not attempted.'; fi

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

if [[ "$DRY_RUN" == true ]]; then
  log_info "[DRY-RUN] would archive the reviewed project and install it under $OFFSEC_INSTALL_ROOT/bootstrap."
else
  bootstrap_target="$OFFSEC_INSTALL_ROOT/bootstrap"
  bootstrap_previous="$OFFSEC_INSTALL_ROOT/.bootstrap-previous"
  if [[ -d "$bootstrap_previous" ]]; then
    if [[ ! -e "$bootstrap_target" ]]; then mv -- "$bootstrap_previous" "$bootstrap_target"
    elif [[ -d "$bootstrap_target" && ! -L "$bootstrap_target" ]]; then safe_remove_tree "$bootstrap_previous" "$OFFSEC_INSTALL_ROOT"
    else die 'Cannot recover an interrupted bootstrap activation.'; fi
  fi
  new_temp_dir stage
  # new_temp_dir validates and assigns this output variable by name.
  # shellcheck disable=SC2154
  tar -C "$PROJECT_ROOT" --exclude='./config/local.conf' --exclude='./.git' -cf "$stage/project.tar" .
  new_bootstrap_stage_dir bootstrap_stage
  # new_bootstrap_stage_dir validates and assigns this output variable by name.
  # shellcheck disable=SC2154
  tar -xf "$stage/project.tar" -C "$bootstrap_stage"
  if [[ -e "$OFFSEC_INSTALL_ROOT/bootstrap/config/local.conf" ]]; then
    existing_local="$OFFSEC_INSTALL_ROOT/bootstrap/config/local.conf"
    [[ -f "$existing_local" && ! -L "$existing_local" && $(stat -c '%u' "$existing_local") == 0 ]] || die "Unsafe installed local configuration: $existing_local"
    install -m 0600 -- "$existing_local" "$bootstrap_stage/config/local.conf"
  fi
  runtime_config="$stage/installed.conf"
  for runtime_name in OFFSEC_PROFILE OFFSEC_DESKTOP OFFSEC_INSTALL_BURP OFFSEC_INSTALL_BLOODHOUND OFFSEC_INSTALL_WORDLISTS OFFSEC_INSTALL_WIRELESS OFFSEC_INSTALL_CLOUD OFFSEC_UPDATE_CHANNEL OFFSEC_ALLOW_DOCKER_GROUP OFFSEC_AUTO_START_SERVICES OFFSEC_INSTALL_ROOT OFFSEC_WORDLIST_ROOT OFFSEC_LOG_ROOT OFFSEC_STATE_ROOT OFFSEC_SAFE_UPGRADE OFFSEC_MIN_FREE_GIB OFFSEC_GDB_PLUGIN OFFSEC_BURP_DOWNLOAD_URL OFFSEC_BURP_SHA256 OFFSEC_METASPLOIT_INSTALLER OFFSEC_WIRESHARK_CAPTURE_GROUP; do
    printf '%s=%q\n' "$runtime_name" "${!runtime_name}" >> "$runtime_config"
  done
  atomic_install_file "$runtime_config" "$bootstrap_stage/config/installed.conf" 0644
  chown -R root:root "$bootstrap_stage"
  bootstrap_target="$OFFSEC_INSTALL_ROOT/bootstrap"
  bootstrap_previous="$OFFSEC_INSTALL_ROOT/.bootstrap-previous"
  [[ ! -L "$bootstrap_target" && ( ! -e "$bootstrap_target" || -d "$bootstrap_target" ) && ! -e "$bootstrap_previous" ]] || die "Unsafe bootstrap activation state."
  if [[ -d "$bootstrap_target" ]]; then mv -- "$bootstrap_target" "$bootstrap_previous"; fi
  if mv -- "$bootstrap_stage" "$bootstrap_target"; then
    if [[ -d "$bootstrap_previous" ]]; then safe_remove_tree "$bootstrap_previous" "$OFFSEC_INSTALL_ROOT"; fi
  else
    if [[ -e "$bootstrap_target" ]]; then safe_remove_tree "$bootstrap_target" "$OFFSEC_INSTALL_ROOT"; fi
    if [[ -d "$bootstrap_previous" ]]; then mv -- "$bootstrap_previous" "$bootstrap_target"; fi
    die 'Failed to activate the staged bootstrap; the previous copy was restored.'
  fi
fi
for helper in offsec-tools offsec-status offsec-update offsec-wordlists offsec-bloodhound offsec-burp offsec-project-new; do install_project_helper_link "$PROJECT_ROOT/scripts/$helper" "/usr/local/bin/$helper"; done
write_inventory
print_result_summary
if [[ "$DRY_RUN" == false ]]; then du -sh "$OFFSEC_INSTALL_ROOT" 2>/dev/null || true; fi
printf 'Verification: sudo %s/bootstrap/verify.sh --profile %s\nWordlists: %s\nLogs: %s\nInventory: %s/inventory.json\nBloodHound: offsec-bloodhound start\nBurp: offsec-burp\n' "$OFFSEC_INSTALL_ROOT" "$OFFSEC_PROFILE" "$OFFSEC_WORDLIST_ROOT" "$OFFSEC_LOG_ROOT" "$OFFSEC_STATE_ROOT"
printf 'Reminder: use these tools only within explicit authorization and scope.\n'
if ((${#OFFSEC_FAILED_REQUIRED[@]})); then exit 1; fi
exit 0
