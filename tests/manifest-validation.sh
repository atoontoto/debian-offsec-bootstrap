#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
quiet=false; [[ ${1:-} == --quiet ]] && quiet=true
failures=0
error() { printf 'manifest error: %s\n' "$*" >&2; failures=$((failures+1)); }
catalog="$ROOT/manifests/tool-catalog.tsv"
[[ -r "$catalog" ]] || { error 'catalog is missing'; exit 1; }
declare -A ids=() channel_ids=() channel_methods=() methods=()
line=1 count=0 core=0 standard=0
while IFS=$'\t' read -r -a field || ((${#field[@]})); do
  line=$((line+1)); [[ -z ${field[0]:-} ]] && continue; count=$((count+1))
  ((${#field[@]} == 17)) || { error "$catalog:$line has ${#field[@]} fields"; continue; }
  id=${field[0]}; [[ -z ${ids[$id]:-} ]] || error "duplicate catalog id: $id"; ids[$id]=1; methods[$id]=${field[3]}
  [[ ${field[9]} =~ ^(true|false)$ && ${field[10]} =~ ^(true|false|optional)$ && ${field[11]} =~ ^(true|false)$ && ${field[12]} =~ ^(true|false)$ ]] || error "$id has invalid boolean fields"
  [[ ${field[6]} =~ ^https?:// && (${field[7]} == - || ${field[7]} =~ ^https://) ]] || error "$id has invalid homepage/source URL"
  [[ ${field[15]} =~ ^(core|standard|full|optional)$ ]] || error "$id has invalid profile"
  [[ ${field[15]} == core ]] && core=$((core+1))
  [[ ${field[15]} == core || ${field[15]} == standard ]] && standard=$((standard+1))
done < <(tail -n +2 "$catalog")
((count >= 100)) || error "catalog has only $count tools"
((core >= 20 && core <= 35)) || error "core profile count $core is outside 20-35"
((standard >= 90 && standard <= 125)) || error "standard profile count $standard is outside 90-125"

while IFS=$'\t' read -r id _ || [[ -n "$id" ]]; do [[ -z "$id" || "$id" == \#* ]] && continue; channel_ids[$id]=1; channel_methods[$id]=pipx; done < "$ROOT/manifests/pipx-tools.txt"
while IFS=$'\t' read -r id _ || [[ -n "$id" ]]; do [[ -z "$id" || "$id" == \#* ]] && continue; channel_ids[$id]=1; channel_methods[$id]=go; done < "$ROOT/manifests/go-tools.tsv"
while IFS=$'\t' read -r id _ || [[ -n "$id" ]]; do [[ -z "$id" || "$id" == \#* ]] && continue; channel_ids[$id]=1; channel_methods[$id]=cargo; done < "$ROOT/manifests/cargo-tools.tsv"
declare -A github_components=() github_commands=()
while IFS=$'\t' read -r -a field || ((${#field[@]})); do
  [[ -z ${field[0]:-} || ${field[0]} == \#* ]] && continue
  id=${field[0]}
  if ((${#field[@]} == 7)); then
    component=$id; repo=${field[1]}; tag=${field[2]}; arch=amd64; regex=${field[3]}; checksum=${field[4]}; mappings=${field[5]}; strip=${field[6]}; verify=-
  elif ((${#field[@]} == 10)); then
    component=${field[1]}; repo=${field[2]}; tag=${field[3]}; arch=${field[4]}; regex=${field[5]}; checksum=${field[6]}; mappings=${field[7]}; strip=${field[8]}; verify=${field[9]}
  else error "github manifest row for $id has ${#field[@]} fields"; continue; fi
  key="$id/$component"; [[ -z ${github_components[$key]:-} ]] || error "duplicate GitHub component: $key"; github_components[$key]=1
  [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || error "$key has invalid GitHub repository"
  [[ $tag =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$ ]] || error "$key is not pinned to a release tag"
  [[ $arch =~ ^(amd64|arm64)$ ]] || error "$key has unsupported architecture"
  [[ ${regex:0:1} == '^' && ${regex: -1} == '$' ]] || error "$key asset regex must be anchored"
  [[ $checksum =~ ^https:// && $checksum != - ]] || error "$key requires an explicit HTTPS checksum URL"
  [[ $strip =~ ^[0-9]+$ ]] || error "$key has invalid strip-components"
  [[ $verify != - && $verify =~ ^[-A-Za-z0-9._+]+$ ]] || error "$key requires safe verification arguments"
  IFS=',' read -r -a map_list <<< "$mappings"
  for mapping in "${map_list[@]}"; do
    if [[ $mapping == *:* ]]; then source_name=${mapping%%:*}; command_name=${mapping#*:}; else source_name=$mapping; command_name=$mapping; fi
    [[ $source_name =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && $command_name =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || error "$key has invalid executable mapping: $mapping"
    github_commands[$id]="${github_commands[$id]:+${github_commands[$id]},}$command_name"
  done
  channel_ids[$id]=1; channel_methods[$id]=github
done < "$ROOT/manifests/github-tools.tsv"
for id in "${!github_commands[@]}"; do
  catalog_exec=$(awk -F '\t' -v wanted="$id" '$1==wanted {print $6; exit}' "$catalog")
  [[ ${github_commands[$id]} == "$catalog_exec" ]] || error "$id GitHub mappings disagree with catalog executables"
done
for id in "${!channel_ids[@]}"; do
  [[ -n ${ids[$id]:-} ]] || { error "channel manifest id is absent from catalog: $id"; continue; }
  [[ ${methods[$id]} == "${channel_methods[$id]}" ]] || error "channel/catalog method mismatch for $id"
done
for id in "${!methods[@]}"; do
  [[ ${methods[$id]} =~ ^(pipx|go|cargo|github)$ ]] || continue
  [[ -n ${channel_ids[$id]:-} ]] || error "catalog $id lacks its ${methods[$id]} channel manifest entry"
done
grep -RIE 'kali\.(org|linux)|http://http\.kali' "$ROOT/config" "$ROOT/manifests/apt-packages.txt" >/dev/null && error 'Kali repository reference found in package configuration'
awk 'NF && $1 !~ /^#/ && NF != 1 {exit 1}' "$ROOT/manifests/apt-packages.txt" || error 'apt manifest must have one package per line'
[[ $failures -eq 0 ]] || exit 1
[[ "$quiet" == true ]] || printf 'Validated %d catalog tools (%d core, %d standard-inclusive).\n' "$count" "$core" "$standard"
