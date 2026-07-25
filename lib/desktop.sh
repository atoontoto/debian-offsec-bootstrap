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
  local user home shellrc aliases
  user=$(invoking_user); [[ "$user" == root ]] && return 0
  home=$(user_home "$user")
  for aliases in aliases.bash aliases.zsh; do run install -m 0644 "$PROJECT_ROOT/config/$aliases" "$home/.offsec-$aliases"; run chown "$user":"$(id -gn "$user")" "$home/.offsec-$aliases"; done
  for shellrc in .bashrc .zshrc; do
    [[ -f "$home/$shellrc" ]] || continue
    grep -Fq '.offsec-aliases' "$home/$shellrc" 2>/dev/null && continue
    backup_file "$home/$shellrc"
    [[ "$DRY_RUN" == true ]] || printf '\n# debian-offsec-bootstrap (remove this line and the next to disable)\n[[ -r "$HOME/.offsec-aliases.%s" ]] && source "$HOME/.offsec-aliases.%s"\n' "${shellrc#.}" "${shellrc#.}" >> "$home/$shellrc"
  done
}
