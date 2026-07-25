#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
compose="$ROOT/docker/bloodhound/compose.yml"
grep -Fq '127.0.0.1:8080:8080' "$compose"
! grep -Eq '0\.0\.0\.0:|^[[:space:]]*-[[:space:]]*"?8080:8080' "$compose"
! grep -Eq 'image:.*:(latest|stable)[[:space:]]*$' "$compose"
grep -Fq 'healthcheck:' "$compose"
if docker compose version >/dev/null 2>&1; then
  BHE_ADMIN_PASSWORD=test POSTGRES_PASSWORD=test NEO4J_PASSWORD=test docker compose -f "$compose" config -q
fi
printf 'Compose validation passed.\n'
