#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

install_burp() {
  local url="$OFFSEC_BURP_DOWNLOAD_URL" digest="$OFFSEC_BURP_SHA256" tmp installer
  if [[ -z "$url" || -z "$digest" ]]; then
    record_skip 'Burp Suite (set OFFSEC_BURP_DOWNLOAD_URL and OFFSEC_BURP_SHA256 after reviewing the PortSwigger license)'
    return 0
  fi
  [[ "$url" =~ ^https://([a-z0-9-]+\.)*portswigger\.net/ ]] || die 'Burp URL must be on an official portswigger.net HTTPS host.'
  if [[ "$DRY_RUN" == true ]]; then record_success 'manual:burpsuite (verified official installer plan)'; return 0; fi
  new_temp_dir tmp; installer="$tmp/burp-installer.sh"
  download_https "$url" "$installer" || { record_failure 'burpsuite download' false; return; }
  verify_sha256 "$installer" "$digest" || { record_failure 'burpsuite checksum' false; return; }
  run chmod 0700 "$installer"
  if run "$installer" -q -dir /opt/burpsuite-community; then
    local launcher marker
    launcher=$(find /opt/burpsuite-community -maxdepth 2 -type f -iname '*Burp*Community*' -print -quit)
    if [[ -n "$launcher" ]]; then install_managed_symlink "$launcher" /usr/local/bin/burpsuite /opt/burpsuite-community; fi
    marker="$tmp/.debian-offsec-bootstrap-owned"
    printf 'debian-offsec-bootstrap\n' > "$marker"
    atomic_install_file "$marker" /opt/burpsuite-community/.debian-offsec-bootstrap-owned 0600
    record_success 'manual:burpsuite'
  else record_failure 'manual:burpsuite' false; fi
}

report_manual_category() {
  local category="$1" row id display
  while IFS= read -r row; do
    IFS=$'\t' read -r id display _ <<< "$row"
    [[ "$id" == burpsuite && "$OFFSEC_INSTALL_BURP" == true ]] && continue
    record_skip "manual:$display (see manifests/manual-tools.tsv)"
  done < <(catalog_rows manual "$category")
}
