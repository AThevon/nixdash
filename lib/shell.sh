#!/usr/bin/env bash
# nixdash — temporary shell

# cmd_shell [PKG...] — enter a temporary nix shell with packages
cmd_shell() {
  # If args provided, launch directly
  if [[ $# -gt 0 ]]; then
    local nix_args=()
    local pkg
    for pkg in "$@"; do
      nix_args+=("nixpkgs#$pkg")
    done
    ui_info "Launching: nix shell ${nix_args[*]}"
    exec nix shell "${nix_args[@]}"
  fi

  # No args — interactive multiselect
  config_ensure

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

  # Build installed set + package list (once)
  local installed_set
  installed_set="$(_search_build_installed_set)"

  local nixdash_bin="$NIXDASH_BIN"

  local pkg_list_file
  pkg_list_file="$(mktemp)"
  nix-search-tv print 2>/dev/null | awk -v installed="$installed_set" '
    BEGIN {
      n = split(installed, arr, "\n")
      for (i = 1; i <= n; i++) inst[arr[i]] = 1
    }
    {
      name = $2
      if (name in inst) printf "✓ %s\n", $0
      else printf "○ %s\n", $0
    }
  ' > "$pkg_list_file"

  # Selection loop — keeps re-opening fzf until user confirms or cancels
  while true; do
    local tmpfile
    tmpfile="$(mktemp)"

    fzf \
      --multi \
      --ansi \
      --height=70% \
      --layout=reverse \
      --border \
      --delimiter " " \
      --header "TAB select · ENTER confirm · ESC cancel" \
      --preview "bash '$nixdash_bin' _search-preview {3}" \
      --preview-window "right:50%:wrap" \
      < "$pkg_list_file" > "$tmpfile" 2>/dev/null

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      rm -f "$tmpfile"
      break
    fi

    # Extract package names
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

    [[ ${#selected[@]} -eq 0 ]] && continue

    # Show recap
    echo >&2
    ui_info "Selected packages (${#selected[@]}):"
    for pkg in "${selected[@]}"; do
      echo -e "  ${COLOR_CYAN}•${COLOR_RESET} $pkg" >&2
    done
    echo >&2

    local action
    action="$(ui_choose "Launch shell?" \
      "»  Launch" \
      "↩  Go back" \
      "✕  Cancel")" || { continue; }

    case "$action" in
      *"Launch"*)
        rm -f "$pkg_list_file"
        local nix_args=()
        for pkg in "${selected[@]}"; do
          nix_args+=("nixpkgs#$pkg")
        done
        ui_info "Launching: nix shell ${nix_args[*]}"
        ui_dim "Type 'exit' to leave the temporary shell."
        nix shell "${nix_args[@]}"
        return 0
        ;;
      *"Cancel"*)
        break
        ;;
      *"Go back"*)
        continue
        ;;
    esac
  done

  rm -f "$pkg_list_file"
}
