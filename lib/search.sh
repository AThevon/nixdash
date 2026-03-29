#!/usr/bin/env bash
# nixdash — package search

# _search_build_installed_set — outputs sorted list of installed package names
_search_build_installed_set() {
  _packages_parse
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    echo "${entry%%|*}"
  done <<< "$_PACKAGES_CACHE" | sort
}

# _search_preview PKG — shows package info from nix-search-tv
_search_preview() {
  local pkg="$1"
  local info
  info="$(nix-search-tv info "$pkg" 2>/dev/null)" || true

  if [[ -z "$info" ]]; then
    echo -e "${COLOR_RED}✗${COLOR_RESET} Package '$pkg' introuvable dans l'index nix-search-tv"
    return 0
  fi

  echo "$info"
}

# search_fzf [--multiselect] [--query "query"] — interactive package search via fzf
# Returns selected package name(s) on stdout
search_fzf() {
  local multiselect=0
  local query=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --multiselect) multiselect=1; shift ;;
      --query) query="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Build installed set for marking
  local installed_set
  installed_set="$(_search_build_installed_set)"

  # Resolve nixdash.sh path for preview
  local nixdash_bin
  nixdash_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/nixdash.sh"

  # Build fzf args
  local fzf_args=(
    --ansi
    --height=70%
    --layout=reverse
    --border
    --header "Recherche de packages Nix"
    --preview "bash '$nixdash_bin' _search-preview {2}"
    --preview-window "right:50%:wrap"
    --delimiter " "
  )

  if [[ -n "$query" ]]; then
    fzf_args+=(--query "$query")
  fi

  if (( multiselect )); then
    fzf_args+=(--multi)
  fi

  # Pipe nix-search-tv through awk to add ✓ markers for installed packages
  local selection
  selection="$(nix-search-tv print 2>/dev/null | awk -v installed="$installed_set" '
    BEGIN {
      n = split(installed, arr, "\n")
      for (i = 1; i <= n; i++) {
        inst[arr[i]] = 1
      }
    }
    {
      name = $2
      if (name in inst) {
        printf "✓ %s\n", $0
      } else {
        printf "  %s\n", $0
      }
    }
  ' | fzf "${fzf_args[@]}")" || return 1

  # Extract package names from selection
  # Format: "✓ nixpkgs/ package_name ..." or "  nixpkgs/ package_name ..."
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Strip ✓ or spaces prefix, strip "nixpkgs/ " prefix, take first field
    line="${line#✓ }"
    line="${line#  }"
    line="${line#nixpkgs/ }"
    echo "${line%% *}"
  done <<< "$selection"
}

# search_is_self PKG — returns 0 if pkg is "nixdash" or starts with "nixdash."
search_is_self() {
  local pkg="$1"
  [[ "$pkg" == "nixdash" || "$pkg" == nixdash.* ]]
}

# cmd_search [QUERY] — interactive search and install/manage packages
cmd_search() {
  config_ensure

  local query=""
  if [[ $# -gt 0 ]]; then
    query="$*"
  fi

  # Run fzf search
  local pkg
  local fzf_args=()
  [[ -n "$query" ]] && fzf_args+=(--query "$query")
  pkg="$(search_fzf "${fzf_args[@]}")" || return 0
  [[ -z "$pkg" ]] && return 0

  # Self-protection
  if search_is_self "$pkg"; then
    ui_warn "Impossible de modifier nixdash depuis nixdash"
    return 0
  fi

  # Check if already installed
  if packages_is_installed "$pkg"; then
    local display_name
    display_name="$(packages_display_name "$pkg")"
    local pkg_type
    pkg_type="$(packages_type "$pkg")"

    local action
    action="$(ui_choose "« $display_name » est déjà installé :" \
      "✕  Supprimer" \
      "◎  Voir en ligne" \
      "↩  Annuler")" || return 0

    case "$action" in
      *"Supprimer")
        _packages_do_remove "$pkg" "$pkg_type"
        ;;
      *"Voir en ligne")
        ui_open_url "https://search.nixos.org/packages?query=$display_name"
        ;;
      *"Annuler")
        return 0
        ;;
    esac
  else
    # Not installed — add it
    local pkg_file
    pkg_file="$(config_get "packages_file")"

    # Backup
    local backup
    backup="$(mktemp)"
    cp "$pkg_file" "$backup"

    # Add package
    packages_add "$pkg"

    # Show diff
    ui_diff "$backup" "$pkg_file"

    # Check auto_apply
    local auto_apply
    auto_apply="$(config_get "auto_apply")"

    if [[ "$auto_apply" == "true" ]]; then
      ui_info "Application automatique..."
    else
      if ! ui_confirm "Installer $pkg ?"; then
        # Restore backup
        cp "$backup" "$pkg_file"
        _PACKAGES_CACHE=""
        ui_warn "Annulé — fichier restauré"
        rm -f "$backup"
        return 1
      fi
    fi

    rm -f "$backup"

    # Run apply command
    local apply_cmd
    apply_cmd="$(config_get "apply_command")"
    ui_info "Exécution : $apply_cmd"
    eval "$apply_cmd"
    ui_success "$pkg installé"
  fi
}
