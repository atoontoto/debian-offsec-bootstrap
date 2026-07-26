#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

desktop_install() {
  local desktop="$1" packages=()
  case "$desktop" in
    none) return 0 ;; xfce) packages=(xfce4 xfce4-terminal thunar) ;; gnome) packages=(gnome-core gnome-terminal) ;; kde) packages=(kde-plasma-desktop konsole dolphin) ;; *) die "Unsupported desktop: $desktop" ;;
  esac
  apt_install_packages false "${packages[@]}"
  run install -d -m 0755 /usr/share/applications
  local file
  for file in "$PROJECT_ROOT"/desktop/*.desktop; do [[ -e "$file" ]] && run install -m 0644 "$file" /usr/share/applications/; done
}

install_shell_integration() {
  local user home shellrc aliases target backup
  user=$(invoking_user); [[ "$user" == root ]] && return 0
  home=$(user_home "$user")
  [[ -d "$home" ]] || die "Invoking user home is not a directory: $home"
  for aliases in aliases.bash aliases.zsh; do
    target="$home/.offsec-$aliases"
    [[ ! -L "$target" ]] || die "Refusing symlinked shell integration file: $target"
    if [[ -f "$target" ]] && ! cmp -s -- "$target" "$PROJECT_ROOT/config/$aliases" && { [[ ! -f "$OFFSEC_INSTALL_ROOT/bootstrap/config/$aliases" ]] || ! cmp -s -- "$target" "$OFFSEC_INSTALL_ROOT/bootstrap/config/$aliases"; }; then
      record_skip "$target was modified and was not overwritten"
      continue
    fi
    run_as_user "$user" install -m 0644 "$PROJECT_ROOT/config/$aliases" "$target"
  done
  for shellrc in .bashrc .zshrc; do
    [[ -f "$home/$shellrc" ]] || continue
    [[ ! -L "$home/$shellrc" ]] || die "Refusing symlinked shell configuration: $home/$shellrc"
    if ! grep -Fq '# debian-offsec-bootstrap (remove this line and the next to disable)' "$home/$shellrc"; then
      backup="${home}/${shellrc}.offsec-backup.$(date -u +%Y%m%dT%H%M%SZ)"
      run_as_user "$user" cp -a -- "$home/$shellrc" "$backup"
    fi
    run_as_user "$user" python3 "$PROJECT_ROOT/scripts/manage-shell-integration.py" add "${shellrc#.}" "$home/$shellrc"
  done
}

desktop_remove_shell_integration() {
  local user home aliases shellrc target
  user=$(invoking_user); [[ "$user" == root ]] && return 0
  home=$(user_home "$user")
  for aliases in aliases.bash aliases.zsh; do
    target="$home/.offsec-$aliases"
    if [[ -f "$target" && ! -L "$target" ]]; then
      if cmp -s -- "$target" "$PROJECT_ROOT/config/$aliases" || { [[ -f "$OFFSEC_INSTALL_ROOT/bootstrap/config/$aliases" ]] && cmp -s -- "$target" "$OFFSEC_INSTALL_ROOT/bootstrap/config/$aliases"; }; then
        run rm -f -- "$target"
      else record_skip "$target was modified and was not removed"; fi
    fi
  done
  for shellrc in .bashrc .zshrc; do
    [[ -f "$home/$shellrc" && ! -L "$home/$shellrc" ]] || continue
    run_as_user "$user" python3 "$PROJECT_ROOT/scripts/manage-shell-integration.py" remove "${shellrc#.}" "$home/$shellrc"
  done
}
