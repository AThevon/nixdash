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
    echo "❌ Package '$pkg' introuvable dans l'index nix-search-tv"
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
    --header "Recherche de packages Nix"
    --preview "bash '$nixdash_bin' _search-preview {1}"
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
      name = $1
      if (name in inst) {
        printf "✓ %s\n", $0
      } else {
        printf "  %s\n", $0
      }
    }
  ' | fzf "${fzf_args[@]}")" || return 1

  # Extract package names from selection (strip marker and take first field)
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Strip ✓ or spaces prefix, take first field (package name)
    line="${line#✓ }"
    line="${line#  }"
    echo "${line%% *}"
  done <<< "$selection"
}

# search_is_self PKG — returns 0 if pkg is "nixdash" or starts with "nixdash."
search_is_self() {
  local pkg="$1"
  [[ "$pkg" == "nixdash" || "$pkg" == nixdash.* ]]
}
