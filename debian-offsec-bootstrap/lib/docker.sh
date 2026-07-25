#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

docker_compose() {
  if docker compose version >/dev/null 2>&1; then docker compose "$@"; elif command -v docker-compose >/dev/null; then docker-compose "$@"; else return 127; fi
}

install_bloodhound_stack() {
  local source="$PROJECT_ROOT/docker/bloodhound" target="$OFFSEC_INSTALL_ROOT/stacks/bloodhound" env_file password
  env_file="$target/.env"
  run install -d -m 0750 -- "$target"
  run install -m 0644 -- "$source/compose.yml" "$target/compose.yml"
  run install -m 0644 -- "$source/README.md" "$target/README.md"
  if [[ ! -e "$env_file" ]]; then
    password=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
    if [[ "$DRY_RUN" == true ]]; then log_info '[DRY-RUN] generate BloodHound .env with a local random password'; else
      umask 077
      { printf 'BHE_ADMIN_PASSWORD=%s\n' "$password"; printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)"; printf 'NEO4J_PASSWORD=%s\n' "$(openssl rand -hex 24)"; printf 'BHE_RECREATE_DEFAULT_ADMIN=false\n'; } > "$env_file"
      chown root:root "$env_file"; chmod 0600 "$env_file"
    fi
  fi
  run install -m 0755 -- "$PROJECT_ROOT/scripts/offsec-bloodhound" /usr/local/bin/offsec-bloodhound
  record_success 'docker:bloodhound-ce (installed, not started)'
  [[ "$OFFSEC_AUTO_START_SERVICES" == true ]] && (cd "$target" && run docker_compose up -d)
}

docker_pull_stacks() {
  local manifest="$PROJECT_ROOT/manifests/docker-stacks.tsv" id compose enabled
  while IFS=$'\t' read -r id compose enabled || [[ -n "$id" ]]; do
    [[ "$id" == id || -z "$id" || "$id" == \#* || "$enabled" != true ]] && continue
    [[ -f "$compose" ]] || compose="$OFFSEC_INSTALL_ROOT/stacks/$id/compose.yml"
    [[ -f "$compose" ]] && run docker_compose -f "$compose" pull || record_failure "docker:$id pull" false
  done < "$manifest"
}

docker_verify_stacks() {
  local file failed=0
  while IFS= read -r -d '' file; do docker_compose -f "$file" config -q || { log_error "Invalid Compose file: $file"; failed=1; }; done < <(find "$PROJECT_ROOT/docker" -name compose.yml -print0)
  return "$failed"
}
