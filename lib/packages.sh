#!/usr/bin/env bash
# nixdash — package listing & management

_PACKAGES_CACHE=""
_FLAKE_PREFIXES=""

# _packages_init_flake_prefixes — reads flake.nix inputs to identify flake prefixes
# Populates _FLAKE_PREFIXES with one prefix per line
_packages_init_flake_prefixes() {
  _FLAKE_PREFIXES=""
  local flake_file
  flake_file="$(config_get "flake_file")"
  [[ -n "$flake_file" && -f "$flake_file" ]] || return 0

  # Extract input names from the inputs block, excluding well-known non-package inputs
  local in_inputs=0
  local line
  while IFS= read -r line; do
    # Detect start of inputs block
    if [[ "$line" =~ ^[[:space:]]*inputs[[:space:]]*=[[:space:]]*\{ ]]; then
      in_inputs=1
      continue
    fi
    # Detect end of inputs block
    if (( in_inputs )) && [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*\; ]]; then
      break
    fi
    if (( in_inputs )); then
      # Match lines like: wt.url = "..."; or wt = { url = "..."; };
      if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)\.(url|inputs) ]]; then
        local name="${BASH_REMATCH[1]}"
        # Skip well-known non-package inputs
        case "$name" in
          nixpkgs|home-manager|flake-utils|systems|nix-darwin|darwin) continue ;;
        esac
        # Only add if not already present
        if [[ ! $'\n'"$_FLAKE_PREFIXES"$'\n' == *$'\n'"$name"$'\n'* ]]; then
          if [[ -n "$_FLAKE_PREFIXES" ]]; then
            _FLAKE_PREFIXES+=$'\n'
          fi
          _FLAKE_PREFIXES+="$name"
        fi
      fi
    fi
  done < "$flake_file"
}

# _packages_is_flake_prefix PREFIX — returns 0 if prefix is a known flake input
_packages_is_flake_prefix() {
  local prefix="$1"
  local p
  while IFS= read -r p; do
    [[ "$p" == "$prefix" ]] && return 0
  done <<< "$_FLAKE_PREFIXES"
  return 1
}

# _packages_detect_type NAME — returns "flake" or "nixpkgs"
_packages_detect_type() {
  local name="$1"
  # If name contains a dot, check if the first segment is a flake prefix
  if [[ "$name" == *.* ]]; then
    local prefix="${name%%.*}"
    # Known nixpkgs prefixes — not flakes
    case "$prefix" in
      nodePackages|python3Packages|python311Packages|python312Packages|\
      perlPackages|rubyPackages|haskellPackages|luaPackages|\
      emacsPackages|vimPlugins|gnomeExtensions|xfce|libsForQt5|\
      plasma5Packages|kdePackages|mate|cinnamon|pantheon)
        echo "nixpkgs"
        return
        ;;
    esac
    if _packages_is_flake_prefix "$prefix"; then
      echo "flake"
      return
    fi
  fi
  echo "nixpkgs"
}

# _packages_parse — parses packages.nix, populates _PACKAGES_CACHE
# Format: "name|type|condition" per line
_packages_parse() {
  _PACKAGES_CACHE=""
  _packages_init_flake_prefixes

  local pkg_file
  pkg_file="$(config_get "packages_file")"
  [[ -n "$pkg_file" && -f "$pkg_file" ]] || return 1

  local in_main_list=0
  local in_conditional=""
  local bracket_depth=0
  local line

  while IFS= read -r line; do
    # Strip comments
    local stripped="${line%%#*}"
    stripped="$(echo "$stripped" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$stripped" ]] && continue

    # Detect home.packages = with pkgs; [
    if [[ "$stripped" =~ home\.packages[[:space:]]*=[[:space:]]* ]]; then
      in_main_list=1
      bracket_depth=1
      continue
    fi

    # Detect conditional blocks: ] ++ lib.optionals stdenv.isLinux [
    if (( in_main_list )) && [[ "$stripped" =~ \]\+\+.*isLinux[[:space:]]*\[ ]] || \
       [[ "$stripped" =~ \][[:space:]]*\+\+.*isLinux[[:space:]]*\[ ]]; then
      in_conditional="linux"
      continue
    fi
    if (( in_main_list )) && [[ "$stripped" =~ \]\+\+.*isDarwin[[:space:]]*\[ ]] || \
       [[ "$stripped" =~ \][[:space:]]*\+\+.*isDarwin[[:space:]]*\[ ]]; then
      in_conditional="darwin"
      continue
    fi

    # Detect end of a list section
    if (( in_main_list )) && [[ "$stripped" =~ ^\] ]]; then
      if [[ -n "$in_conditional" ]]; then
        # End of conditional block
        in_conditional=""
        # Check if there's a ]; to end everything
        if [[ "$stripped" == "];" ]]; then
          in_main_list=0
          break
        fi
        continue
      else
        # End of main list, but could be followed by ++
        if [[ "$stripped" == "];" ]]; then
          in_main_list=0
          break
        fi
        # ] ++ ... continues
        continue
      fi
    fi

    # If we're inside a list, extract package name
    if (( in_main_list )); then
      # Skip lines that are clearly not package names
      [[ "$stripped" == "{"* ]] && continue
      [[ "$stripped" == "}"* ]] && continue
      [[ "$stripped" == "let"* ]] && continue
      [[ "$stripped" == "in"* ]] && continue

      local pkg_name="$stripped"
      local pkg_type
      pkg_type="$(_packages_detect_type "$pkg_name")"
      local condition="${in_conditional}"

      local entry="${pkg_name}|${pkg_type}|${condition}"
      if [[ -n "$_PACKAGES_CACHE" ]]; then
        _PACKAGES_CACHE+=$'\n'
      fi
      _PACKAGES_CACHE+="$entry"
    fi
  done < "$pkg_file"
}

# packages_list — outputs all package names, one per line
packages_list() {
  _packages_parse
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    echo "${entry%%|*}"
  done <<< "$_PACKAGES_CACHE"
}

# packages_type PKG — returns "nixpkgs" or "flake"
packages_type() {
  local pkg="$1"
  _packages_parse
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local name="${entry%%|*}"
    if [[ "$name" == "$pkg" ]]; then
      local rest="${entry#*|}"
      echo "${rest%%|*}"
      return 0
    fi
  done <<< "$_PACKAGES_CACHE"
  echo "nixpkgs"
}

# packages_condition PKG — returns "linux", "darwin", or ""
packages_condition() {
  local pkg="$1"
  _packages_parse
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local name="${entry%%|*}"
    if [[ "$name" == "$pkg" ]]; then
      local rest="${entry#*|}"
      local condition="${rest#*|}"
      echo "$condition"
      return 0
    fi
  done <<< "$_PACKAGES_CACHE"
  echo ""
}

# packages_is_installed PKG — returns 0 if found, 1 if not
packages_is_installed() {
  local pkg="$1"
  _packages_parse
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local name="${entry%%|*}"
    [[ "$name" == "$pkg" ]] && return 0
  done <<< "$_PACKAGES_CACHE"
  return 1
}

# packages_add PKG — inserts package before the first ]; after home.packages
packages_add() {
  local pkg="$1"
  local pkg_file
  pkg_file="$(config_get "packages_file")"
  [[ -n "$pkg_file" && -f "$pkg_file" ]] || return 1

  # Find the first ]; after home.packages and insert before it
  local tmpfile
  tmpfile="$(mktemp)"
  local found_packages=0
  local inserted=0

  while IFS= read -r line; do
    if [[ "$line" =~ home\.packages ]]; then
      found_packages=1
    fi
    # Insert before the first ] that closes the main list
    if (( found_packages && !inserted )); then
      local stripped
      stripped="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [[ "$stripped" == "]"* ]]; then
        # Detect indentation from previous lines in the file
        local indent="    "
        printf '%s%s\n' "$indent" "$pkg" >> "$tmpfile"
        inserted=1
      fi
    fi
    printf '%s\n' "$line" >> "$tmpfile"
  done < "$pkg_file"

  mv "$tmpfile" "$pkg_file"
  # Invalidate cache
  _PACKAGES_CACHE=""
}

# packages_remove PKG — removes the line matching the package name
packages_remove() {
  local pkg="$1"
  local pkg_file
  pkg_file="$(config_get "packages_file")"
  [[ -n "$pkg_file" && -f "$pkg_file" ]] || return 1

  local tmpfile
  tmpfile="$(mktemp)"

  while IFS= read -r line; do
    local stripped
    stripped="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Skip the line that matches the package exactly
    [[ "$stripped" == "$pkg" ]] && continue
    printf '%s\n' "$line" >> "$tmpfile"
  done < "$pkg_file"

  mv "$tmpfile" "$pkg_file"
  # Invalidate cache
  _PACKAGES_CACHE=""
}

# packages_display_name PKG — returns short name for flake packages, name as-is for nixpkgs
packages_display_name() {
  local pkg="$1"
  # Ensure flake prefixes are loaded (may run in subshell via `run`)
  [[ -z "$_FLAKE_PREFIXES" ]] && _packages_init_flake_prefixes
  local pkg_type
  pkg_type="$(_packages_detect_type "$pkg")"
  if [[ "$pkg_type" == "flake" ]]; then
    echo "${pkg%%.*}"
  else
    echo "$pkg"
  fi
}

# packages_format_line NAME TYPE CONDITION — formats a line for fzf display
packages_format_line() {
  local name="$1" type="$2" condition="${3:-}"
  local indicator=""
  if [[ "$type" == "flake" ]]; then
    indicator=" [flake]"
  fi
  if [[ -n "$condition" ]]; then
    indicator+=" ($condition)"
  fi
  echo "${name}${indicator}"
}

# _packages_do_remove FULL_NAME PKG_TYPE — remove a package with backup, diff, confirm, apply
_packages_do_remove() {
  local full_name="$1"
  local pkg_type="${2:-nixpkgs}"

  local pkg_file
  pkg_file="$(config_get "packages_file")"

  # Backup
  local backup
  backup="$(mktemp)"
  cp "$pkg_file" "$backup"

  # Remove from packages file
  packages_remove "$full_name"

  # If flake, also remove flake input
  if [[ "$pkg_type" == "flake" ]]; then
    local prefix="${full_name%%.*}"
    if type flake_remove_input &>/dev/null; then
      flake_remove_input "$prefix"
    fi
  fi

  # Show diff
  ui_diff "$backup" "$pkg_file"

  # Check auto_apply
  local auto_apply
  auto_apply="$(config_get "auto_apply")"

  if [[ "$auto_apply" == "true" ]]; then
    ui_info "Application automatique..."
  else
    if ! ui_confirm "Appliquer les changements ?"; then
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
  ui_success "Changements appliqués"
}

# cmd_list — interactive list of installed packages with actions
cmd_list() {
  config_ensure
  _packages_parse

  [[ -z "$_PACKAGES_CACHE" ]] && { ui_warn "Aucun package trouvé"; return 0; }

  # Build fzf input
  local fzf_input=""
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local name="${entry%%|*}"
    local rest="${entry#*|}"
    local type="${rest%%|*}"
    local condition="${rest#*|}"
    local line
    line="$(packages_format_line "$name" "$type" "$condition")"
    if [[ -n "$fzf_input" ]]; then
      fzf_input+=$'\n'
    fi
    fzf_input+="$line"
  done <<< "$_PACKAGES_CACHE"

  # Resolve nixdash.sh path for preview
  local nixdash_bin
  nixdash_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/nixdash.sh"

  # Show in fzf
  local selection
  selection="$(echo "$fzf_input" | fzf \
    --ansi \
    --header "Packages installés" \
    --preview "bash '$nixdash_bin' _search-preview {1}" \
    --preview-window "right:50%:wrap")" || return 0

  # Extract package name (first word before any markers)
  local display_name="${selection%% *}"

  # Resolve display name back to full package name
  local full_name="$display_name"
  local pkg_type="nixpkgs"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local name="${entry%%|*}"
    local rest="${entry#*|}"
    local type="${rest%%|*}"
    local dname
    dname="$(packages_display_name "$name")"
    if [[ "$dname" == "$display_name" ]]; then
      full_name="$name"
      pkg_type="$type"
      break
    fi
  done <<< "$_PACKAGES_CACHE"

  # Self-protection
  if search_is_self "$full_name"; then
    ui_warn "Impossible de modifier nixdash depuis nixdash"
    return 0
  fi

  # Action menu
  local action
  action="$(ui_choose "Action pour $display_name :" \
    "🗑️  Supprimer" \
    "🌐 Voir en ligne" \
    "❌ Annuler")" || return 0

  case "$action" in
    "🗑️  Supprimer")
      _packages_do_remove "$full_name" "$pkg_type"
      ;;
    "🌐 Voir en ligne")
      if [[ "$pkg_type" == "flake" ]]; then
        # Try to get URL from flake.nix
        local flake_file
        flake_file="$(config_get "flake_file")"
        local prefix="${full_name%%.*}"
        local url=""
        if [[ -n "$flake_file" && -f "$flake_file" ]]; then
          url="$(grep -oP "${prefix}\\.url\\s*=\\s*\"\\Kgithub:[^\"]*" "$flake_file" 2>/dev/null | head -1)" || true
        fi
        if [[ -n "$url" ]]; then
          # Convert github:owner/repo to https://github.com/owner/repo
          local gh_url="https://github.com/${url#github:}"
          gh_url="${gh_url%%/*([^/])}"
          ui_open_url "$gh_url"
        else
          ui_warn "URL introuvable pour $prefix"
        fi
      else
        ui_open_url "https://search.nixos.org/packages?query=$display_name"
      fi
      ;;
    "❌ Annuler")
      return 0
      ;;
  esac
}
