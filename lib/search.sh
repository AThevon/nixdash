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
  [[ -z "$pkg" ]] && return 0

  local info
  info="$(nix-search-tv preview "nixpkgs/ $pkg" 2>/dev/null)" || true

  if [[ -z "$info" ]]; then
    echo "Package '$pkg' — no info available"
    return 0
  fi

  echo "$info"
}

# search_fzf [--query "query"] — interactive single-select package search via fzf
# Returns selected package name on stdout
search_fzf() {
  local query=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query) query="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Build installed set for marking
  local installed_set
  installed_set="$(_search_build_installed_set)"

  local nixdash_bin="$NIXDASH_BIN"

  # Build fzf args
  local fzf_args=(
    --ansi
    --height=70%
    --layout=reverse
    --border
    --delimiter " "
  )

  if [[ -n "$query" ]]; then
    fzf_args+=(--query "$query")
  fi

  fzf_args+=(
    --preview "bash '$nixdash_bin' _search-preview {3}"
    --preview-window "right:50%:wrap"
  )

  fzf_args+=(--header "Search Nix packages")

  # Check if index exists, fetch if empty
  local pkg_count
  pkg_count="$(nix-search-tv print 2>/dev/null | head -1 | wc -l)"
  if [[ "$pkg_count" -eq 0 ]]; then
    ui_warn "nix-search-tv index is empty"
    if ui_confirm "Download package index now? (this may take a moment)"; then
      ui_spin "Fetching nix-search-tv index..." nix-search-tv fetch
      ui_success "Index ready"
    else
      ui_error "Cannot search without an index"
      return 1
    fi
  fi

  # Pipe nix-search-tv through awk to add ✓ markers for installed packages
  local tmpfile installed_file
  tmpfile="$(mktemp)"
  installed_file="$(mktemp)"
  echo "$installed_set" > "$installed_file"

  nix-search-tv print 2>/dev/null | awk -v installed_file="$installed_file" '
    BEGIN {
      while ((getline line < installed_file) > 0) inst[line] = 1
      close(installed_file)
    }
    {
      name = $2
      if (name in inst) {
        printf "✓ %s\n", $0
      } else {
        printf "○ %s\n", $0
      }
    }
  ' | fzf "${fzf_args[@]}" > "$tmpfile" || { rm -f "$tmpfile" "$installed_file"; return 1; }

  rm -f "$installed_file"

  local selection
  selection="$(cat "$tmpfile")"
  rm -f "$tmpfile"

  # Extract package names from selection
  # Format: "✓ nixpkgs/ package_name ..." or "○ nixpkgs/ package_name ..."
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Strip marker + "nixpkgs/ " prefix, take first field (package name)
    line="${line#✓ }"
    line="${line#○ }"
    line="${line#nixpkgs/ }"
    echo "${line%% *}"
  done <<< "$selection"
}

# search_is_self PKG — returns 0 if pkg is "nixdash" or starts with "nixdash."
search_is_self() {
  local pkg="$1"
  [[ "$pkg" == "nixdash" || "$pkg" == nixdash.* ]]
}

# _search_install_packages PKG... — install one or more packages with diff + confirm
_search_install_packages() {
  local pkgs=("$@")
  local pkg_file
  pkg_file="$(config_get "packages_file")"

  local backup
  backup="$(mktemp)"
  cp "$pkg_file" "$backup"

  local added=0
  for pkg in "${pkgs[@]}"; do
    if packages_is_installed "$pkg"; then
      ui_dim "  $pkg already installed, skipping" >&2
    else
      packages_add "$pkg"
      ((added++))
    fi
  done

  if [[ $added -eq 0 ]]; then
    ui_warn "All packages already installed"
    rm -f "$backup"
    return 0
  fi

  ui_diff "$backup" "$pkg_file"

  local skip_confirmation
  skip_confirmation="$(config_get "skip_confirmation")"

  if [[ "$skip_confirmation" != "true" ]]; then
    if ! ui_confirm "Install $added package(s)?"; then
      cp "$backup" "$pkg_file"
      _PACKAGES_CACHE=""
      ui_warn "Cancelled — file restored"
      rm -f "$backup"
      return 0
    fi
  fi

  rm -f "$backup"

  local apply_cmd
  apply_cmd="$(config_get "apply_command")"
  ui_info "Running: $apply_cmd"
  eval "$apply_cmd"
  ui_success "$added package(s) installed"
  return 10
}

# cmd_search [QUERY] — interactive search and install/manage packages
cmd_search() {
  config_ensure

  local query=""
  if [[ $# -gt 0 ]]; then
    query="$*"
  fi

  # Run fzf search (multiselect with TAB)
  local fzf_args=(--query "${query:-}")

  # Check index
  local idx_count
  idx_count="$(nix-search-tv print 2>/dev/null | head -1 | wc -l)"
  if [[ "$idx_count" -eq 0 ]]; then
    ui_warn "nix-search-tv index is empty"
    if ui_confirm "Download package index now?"; then
      ui_spin "Fetching nix-search-tv index..." nix-search-tv fetch
      ui_success "Index ready"
    else
      ui_error "Cannot search without an index"
      return 1
    fi
  fi

  local installed_set
  installed_set="$(_search_build_installed_set)"
  local nixdash_bin="$NIXDASH_BIN"

  local pkg_list_file installed_file
  pkg_list_file="$(mktemp)"
  installed_file="$(mktemp)"
  echo "$installed_set" > "$installed_file"

  local attempt
  for attempt in 1 2 3; do
    ui_info "Loading packages..." >&2
    nix-search-tv print 2>/dev/null | awk -v installed_file="$installed_file" '
      BEGIN {
        while ((getline line < installed_file) > 0) inst[line] = 1
        close(installed_file)
      }
      /^nixpkgs\// {
        name = $2
        if (name in inst) printf "✓ %s\n", $0
        else printf "○ %s\n", $0
      }
    ' > "$pkg_list_file"

    local line_count
    line_count="$(wc -l < "$pkg_list_file")"
    if [[ "$line_count" -ge 10 ]]; then
      break
    fi

    if [[ $attempt -lt 3 ]]; then
      ui_warn "Package list incomplete, retrying..." >&2
      sleep 1
    else
      ui_error "Failed to load package list after 3 attempts"
      rm -f "$pkg_list_file" "$installed_file"
      return 1
    fi
  done

  local tmpfile
  tmpfile="$(mktemp)"

  fzf \
    --multi \
    --ansi \
    --height=70% \
    --layout=reverse \
    --border \
    --delimiter " " \
    --with-nth "1,3.." \
    --header "Search Nix packages" \
    --footer "TAB select · ENTER confirm · ESC cancel" \
    --preview "bash '$nixdash_bin' _search-preview {3}" \
    --preview-window "right:50%:wrap" \
    --query "${query:-}" \
    < "$pkg_list_file" > "$tmpfile" 2>/dev/null

  local exit_code=$?
  rm -f "$pkg_list_file" "$installed_file"

  if [[ $exit_code -ne 0 ]]; then
    rm -f "$tmpfile"
    return 0
  fi

  # Extract selected package names
  local selected=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    line="${line#✓ }"
    line="${line#○ }"
    line="${line#nixpkgs/ }"
    local pkg_name="${line%% *}"
    [[ -n "$pkg_name" ]] && selected+=("$pkg_name")
  done < "$tmpfile"
  rm -f "$tmpfile"

  [[ ${#selected[@]} -eq 0 ]] && return 0

  # Single selection — show action menu
  if [[ ${#selected[@]} -eq 1 ]]; then
    local pkg="${selected[0]}"

    if search_is_self "$pkg"; then
      ui_warn "Cannot modify nixdash from within nixdash"
      return 0
    fi

    if packages_is_installed "$pkg"; then
      local display_name
      display_name="$(packages_display_name "$pkg")"
      local pkg_type
      pkg_type="$(packages_type "$pkg")"

      local action
      action="$(ui_choose "\"$display_name\" is already installed:" \
        "✕  Remove" \
        "◎  View online" \
        "↩  Cancel")" || return 0

      case "$action" in
        *"Remove")
          _packages_do_remove "$pkg" "$pkg_type"
          return 10
          ;;
        *"View online")
          ui_open_url "https://search.nixos.org/packages?query=$display_name"
          ;;
      esac
      return 0
    else
      local action
      action="$(ui_choose "$pkg:" \
        "⊕  Install" \
        "»  Test in a shell" \
        "↩  Cancel")" || return 0

      case "$action" in
        *"Install")
          _search_install_packages "$pkg"
          return $?
          ;;
        *"Test"*)
          ui_info "Launching temporary shell with $pkg..."
          ui_dim "Type 'exit' to leave. Run 'nixdash' to install."
          export NIXDASH_SHELL_PKGS="$pkg"
          nix shell "nixpkgs#$pkg"
          return 0
          ;;
      esac
      return 0
    fi
  fi

  # Multiple selection — batch install
  _search_install_packages "${selected[@]}"
  return $?
}
