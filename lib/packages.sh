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

  # Strategy: extract input names from flake.nix inputs block
  # Supports both formats:
  #   wt.url = "...";
  #   wt = { url = "..."; };
  local in_inputs=0
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*inputs[[:space:]]*=[[:space:]]*\{ ]]; then
      in_inputs=1
      continue
    fi
    if (( in_inputs )) && [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*\; ]]; then
      break
    fi
    if (( in_inputs )); then
      local name=""
      # Format: wt.url = "..."; or wt.inputs...
      if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)\.(url|inputs) ]]; then
        name="${BASH_REMATCH[1]}"
      # Format: wt = { or wt = {
      elif [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*\{ ]]; then
        name="${BASH_REMATCH[1]}"
      fi

      [[ -z "$name" ]] && continue

      # Skip well-known non-package inputs
      case "$name" in
        nixpkgs|home-manager|flake-utils|systems|nix-darwin|darwin) continue ;;
      esac
      # Only add if not already present
      if [[ ! $'\n'"$_FLAKE_PREFIXES"$'\n' == *$'\n'"$name"$'\n'* ]]; then
        [[ -n "$_FLAKE_PREFIXES" ]] && _FLAKE_PREFIXES+=$'\n'
        _FLAKE_PREFIXES+="$name"
      fi
    fi
  done < "$flake_file"

  # Also check extraSpecialArgs to find what names are actually passed to modules
  # This helps match "zigpkgs" (passed arg) vs "zig-overlay" (input name)
  local esa_line
  esa_line="$(grep -n "extraSpecialArgs" "$flake_file" 2>/dev/null | head -1 | cut -d: -f1)" || true
  if [[ -n "$esa_line" ]]; then
    # Read a few lines after extraSpecialArgs to find inherit statements
    local inherit_names
    inherit_names="$(awk -v start="$esa_line" '
      NR >= start && NR <= start+5 && /inherit/ {
        gsub(/inherit|;|\{|\}/, "")
        print
      }
    ' "$flake_file" | xargs -n1 2>/dev/null)" || true

    # Add any names from extraSpecialArgs that aren't already known
    local iname
    for iname in $inherit_names; do
      case "$iname" in
        system|username|nixpkgs|home-manager|self) continue ;;
      esac
      if [[ ! $'\n'"$_FLAKE_PREFIXES"$'\n' == *$'\n'"$iname"$'\n'* ]]; then
        [[ -n "$_FLAKE_PREFIXES" ]] && _FLAKE_PREFIXES+=$'\n'
        _FLAKE_PREFIXES+="$iname"
      fi
    done
  fi
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
      plasma5Packages|kdePackages|qt6Packages|mate|cinnamon|pantheon|\
      nerd-fonts|akkuPackages)
        echo "nixpkgs"
        return
        ;;
    esac
    if _packages_is_flake_prefix "$prefix"; then
      echo "flake"
      return
    fi
    # If prefix is unknown (not in our nixpkgs list), treat as flake/custom
    # This catches overlays like zigpkgs.master and flake inputs
    echo "flake"
    return
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

  # If it's a flake input (e.g. envoy.packages.${system}.default),
  # ensure the input name is in the function arguments (first line)
  local input_name="${pkg%%.*}"
  if [[ "$pkg" == *".packages."* ]] && ! head -1 "$pkg_file" | grep -qw "$input_name"; then
    sed -i "1s/\.\.\./$(printf '%s' "$input_name"), .../" "$pkg_file"
  fi

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

  # If it was a flake input, remove the input name from function arguments
  local input_name="${pkg%%.*}"
  if [[ "$pkg" == *".packages."* ]] && head -1 "$pkg_file" | grep -qw "$input_name"; then
    # Check no other package uses this input
    if ! grep -q "${input_name}\." "$pkg_file" 2>/dev/null; then
      sed -i "1s/, *${input_name}//" "$pkg_file"
    fi
  fi

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

  # Check skip_confirmation
  local skip_confirmation
  skip_confirmation="$(config_get "skip_confirmation")"

  if [[ "$skip_confirmation" == "true" ]]; then
    ui_info "Auto-applying..."
  else
    if ! ui_confirm "Apply changes?"; then
      # Restore backup
      cp "$backup" "$pkg_file"
      _PACKAGES_CACHE=""
      ui_warn "Cancelled — file restored"
      rm -f "$backup"
      return 1
    fi
  fi

  rm -f "$backup"

  # Run apply command
  local apply_cmd
  apply_cmd="$(config_get "apply_command")"
  ui_info "Running: $apply_cmd"
  eval "$apply_cmd"
  ui_success "Changes applied"
  return 10
}

# _list_preview — preview for the list view (handles both nixpkgs and flakes)
_list_preview() {
  local item="$1"
  [[ -z "$item" ]] && return 0

  # Separator lines
  [[ "$item" == "──"* ]] && return 0

  # Check if it's a flake item (starts with ⚡)
  if [[ "$item" == "⚡" ]]; then
    local display_name="$2"
    [[ -z "$display_name" ]] && return 0

    # Get flake URL from flake.nix — try multiple patterns
    local flake_file
    flake_file="$(config_get "flake_file")"
    local url=""
    if [[ -n "$flake_file" && -f "$flake_file" ]]; then
      # Try direct match: name.url = "...";
      url="$(grep -oP "${display_name}\\.url\\s*=\\s*\"\\K[^\"]*" "$flake_file" 2>/dev/null | head -1)" || true

      # Try block match: name = { url = "..."; };
      if [[ -z "$url" ]]; then
        url="$(awk -v name="$display_name" '
          $0 ~ "^[[:space:]]*" name "[[:space:]]*=" { found=1 }
          found && /url[[:space:]]*=/ {
            match($0, /url[[:space:]]*=[[:space:]]*"([^"]*)"/, m)
            if (m[1]) { print m[1]; exit }
          }
          found && /\}/ { found=0 }
        ' "$flake_file" 2>/dev/null)" || true
      fi

      # Try searching all URLs for a match on the display name
      if [[ -z "$url" ]]; then
        url="$(grep -oP 'url\s*=\s*"\K[^"]*'"$display_name"'[^"]*' "$flake_file" 2>/dev/null | head -1)" || true
      fi
    fi

    echo "Flake input: $display_name"
    echo "─────────────────────────"
    echo ""
    if [[ -n "$url" ]]; then
      echo "URL:  $url"
      if [[ "$url" == github:* ]]; then
        echo "Repo: https://github.com/${url#github:}"
      fi
    else
      echo "Type: Overlay / custom package"
      echo ""
      echo "This package is provided via an overlay"
      echo "or a custom Nix expression, not a direct"
      echo "flake input."
    fi
    echo ""
    echo "Source: External (not from nixpkgs)"
    return 0
  fi

  # Strip condition suffix like "(linux)" for nix-search-tv lookup
  local pkg_name="${item%% (*}"

  # Regular nixpkgs package — use nix-search-tv
  _search_preview "$pkg_name"
}

# cmd_list — interactive list of installed packages with actions
cmd_list() {
  config_ensure
  _packages_parse

  [[ -z "$_PACKAGES_CACHE" ]] && { ui_warn "No packages found"; return 0; }

  # Separate packages into groups
  local flakes="" nixpkgs_main="" nixpkgs_cond=""
  local entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local name="${entry%%|*}"
    local rest="${entry#*|}"
    local type="${rest%%|*}"
    local condition="${rest#*|}"
    if [[ "$type" == "flake" ]]; then
      local dname
      dname="$(packages_display_name "$name")"
      flakes+="⚡ ${dname}"$'\n'
    elif [[ -n "$condition" ]]; then
      nixpkgs_cond+="${name} ($condition)"$'\n'
    else
      nixpkgs_main+="${name}"$'\n'
    fi
  done <<< "$_PACKAGES_CACHE"

  # Build grouped fzf input
  local fzf_input=""
  if [[ -n "$flakes" ]]; then
    fzf_input+="── Flake inputs ──────────────────"$'\n'
    fzf_input+="${flakes}"
  fi
  if [[ -n "$nixpkgs_main" ]]; then
    fzf_input+="── Packages ──────────────────────"$'\n'
    fzf_input+="${nixpkgs_main}"
  fi
  if [[ -n "$nixpkgs_cond" ]]; then
    fzf_input+="── Platform-specific ─────────────"$'\n'
    fzf_input+="${nixpkgs_cond}"
  fi

  # Remove trailing newline
  fzf_input="${fzf_input%$'\n'}"

  local nixdash_bin="$NIXDASH_BIN"

  # Show in fzf
  local tmpfile
  tmpfile="$(mktemp)"

  echo "$fzf_input" | fzf \
    --multi \
    --ansi \
    --height=70% \
    --layout=reverse \
    --border \
    --no-sort \
    --header "Installed packages" \
    --footer "TAB select · ENTER confirm · ESC cancel" \
    --preview "bash '$nixdash_bin' _list-preview {1} {2}" \
    --preview-window "right:50%:wrap" \
  > "$tmpfile" || { rm -f "$tmpfile"; return 0; }

  # Parse all selected lines
  local selected_names=()
  local selected_full=()
  local selected_types=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Skip separators
    [[ "$line" == "──"* ]] && continue

    local display_name
    if [[ "$line" == "⚡ "* ]]; then
      display_name="${line#⚡ }"
      display_name="${display_name%% *}"
    else
      display_name="${line%% *}"
    fi

    # Resolve to full name
    local full_name="$display_name" pkg_type="nixpkgs"
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

    selected_names+=("$display_name")
    selected_full+=("$full_name")
    selected_types+=("$pkg_type")
  done < "$tmpfile"
  rm -f "$tmpfile"

  [[ ${#selected_names[@]} -eq 0 ]] && return 0

  # Single selection — show action menu (remove, view online, cancel)
  if [[ ${#selected_names[@]} -eq 1 ]]; then
    local display_name="${selected_names[0]}"
    local full_name="${selected_full[0]}"
    local pkg_type="${selected_types[0]}"

    if search_is_self "$full_name"; then
      ui_warn "Cannot modify nixdash from within nixdash"
      return 0
    fi

    local action
    action="$(ui_choose "Action for $display_name:" \
      "✕  Remove" \
      "◎  View online" \
      "↩  Cancel")" || return 0

    case "$action" in
      *"Remove")
        _packages_do_remove "$full_name" "$pkg_type"
        return $?
        ;;
      *"View online")
        if [[ "$pkg_type" == "flake" ]]; then
          local flake_file
          flake_file="$(config_get "flake_file")"
          local prefix="${full_name%%.*}"
          local url=""
          if [[ -n "$flake_file" && -f "$flake_file" ]]; then
            url="$(grep -oP "${prefix}\\.url\\s*=\\s*\"\\Kgithub:[^\"]*" "$flake_file" 2>/dev/null | head -1)" || true
          fi
          if [[ -n "$url" ]]; then
            local gh_url="https://github.com/${url#github:}"
            ui_open_url "$gh_url"
          else
            ui_warn "URL not found for $prefix"
          fi
        else
          ui_open_url "https://search.nixos.org/packages?query=$display_name"
        fi
        ;;
    esac
    return 0
  fi

  # Multiple selection — batch remove
  # Filter out self-protected packages
  local to_remove_names=() to_remove_full=() to_remove_types=()
  for i in "${!selected_names[@]}"; do
    if search_is_self "${selected_full[$i]}"; then
      ui_warn "Skipping nixdash (cannot remove itself)"
    else
      to_remove_names+=("${selected_names[$i]}")
      to_remove_full+=("${selected_full[$i]}")
      to_remove_types+=("${selected_types[$i]}")
    fi
  done

  [[ ${#to_remove_names[@]} -eq 0 ]] && return 0

  echo >&2
  ui_info "Packages to remove (${#to_remove_names[@]}):"
  for name in "${to_remove_names[@]}"; do
    echo -e "  ${COLOR_RED}✕${COLOR_RESET} $name" >&2
  done
  echo >&2

  local pkg_file
  pkg_file="$(config_get "packages_file")"
  local flake_file
  flake_file="$(config_get "flake_file")"

  local backup_pkg backup_flake
  backup_pkg="$(mktemp)"
  backup_flake="$(mktemp)"
  cp "$pkg_file" "$backup_pkg"
  cp "$flake_file" "$backup_flake"

  for i in "${!to_remove_full[@]}"; do
    packages_remove "${to_remove_full[$i]}"
    if [[ "${to_remove_types[$i]}" == "flake" ]]; then
      local prefix="${to_remove_full[$i]%%.*}"
      flake_remove_input "$prefix" 2>/dev/null || true
    fi
  done

  ui_info "Changes in packages.nix:"
  ui_diff "$backup_pkg" "$pkg_file"
  if ! diff -q "$backup_flake" "$flake_file" &>/dev/null; then
    ui_info "Changes in flake.nix:"
    ui_diff "$backup_flake" "$flake_file"
  fi

  if ! ui_confirm "Remove ${#to_remove_names[@]} package(s)?"; then
    cp "$backup_pkg" "$pkg_file"
    cp "$backup_flake" "$flake_file"
    _PACKAGES_CACHE=""
    ui_warn "Cancelled — files restored"
    rm -f "$backup_pkg" "$backup_flake"
    return 0
  fi

  rm -f "$backup_pkg" "$backup_flake"

  local apply_cmd
  apply_cmd="$(config_get "apply_command")"
  ui_info "Running: $apply_cmd"
  eval "$apply_cmd"
  ui_success "${#to_remove_names[@]} package(s) removed"
  return 10
}
