#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

docker_compose() {
  if docker compose version >/dev/null 2>&1; then docker compose "$@"; elif command -v docker-compose >/dev/null; then docker-compose "$@"; else return 127; fi
}

install_bloodhound_stack() {
  local source="$PROJECT_ROOT/docker/bloodhound" target="$OFFSEC_INSTALL_ROOT/stacks/bloodhound" env_file password
  env_file="$target/.env"
  ensure_managed_directory "$target" "$OFFSEC_INSTALL_ROOT" 0750
  run install -m 0644 -- "$source/compose.yml" "$target/compose.yml"
  run install -m 0644 -- "$source/README.md" "$target/README.md"
  if [[ "$DRY_RUN" == true ]]; then
    log_info '[DRY-RUN] would generate a root-only BloodHound .env with local random passwords if absent.'
    record_success 'docker:bloodhound-ce (installed, not started)'
    if [[ "$OFFSEC_AUTO_START_SERVICES" == true ]]; then run docker_compose -f "$target/compose.yml" up -d; fi
    return 0
  fi
  if [[ ! -e "$env_file" ]]; then
    password=$(openssl rand -hex 16)
    umask 077
    { printf 'BHE_ADMIN_PASSWORD=%s\n' "$password"; printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)"; printf 'NEO4J_PASSWORD=%s\n' "$(openssl rand -hex 24)"; printf 'BHE_RECREATE_DEFAULT_ADMIN=false\n'; } > "$env_file"
    chown root:root "$env_file"; chmod 0600 "$env_file"
  fi
  record_success 'docker:bloodhound-ce (installed, not started)'
  if [[ "$OFFSEC_AUTO_START_SERVICES" == true ]]; then (cd "$target" && run docker_compose up -d); fi
  return 0
}

docker_pull_stacks() {
  local manifest="$PROJECT_ROOT/manifests/docker-stacks.tsv" id compose enabled
  while IFS=$'\t' read -r id compose enabled || [[ -n "$id" ]]; do
    [[ "$id" == id || -z "$id" || "$id" == \#* || "$enabled" != true ]] && continue
    if [[ "$id" == bloodhound && "$OFFSEC_INSTALL_BLOODHOUND" != true ]]; then record_skip 'docker:bloodhound (disabled)'; continue; fi
    [[ "$compose" == /* ]] || compose="$OFFSEC_INSTALL_ROOT/$compose"
    [[ -f "$compose" ]] || compose="$OFFSEC_INSTALL_ROOT/stacks/$id/compose.yml"
    if [[ -f "$compose" ]]; then run docker_compose -f "$compose" pull || record_failure "docker:$id pull" false
    else record_skip "docker:$id is not installed"; fi
  done < "$manifest"
}

docker_verify_stacks() {
  local file failed=0
  while IFS= read -r -d '' file; do docker_compose -f "$file" config -q || { log_error "Invalid Compose file: $file"; failed=1; }; done < <(find "$PROJECT_ROOT/docker" -name compose.yml -print0)
  return "$failed"
}
