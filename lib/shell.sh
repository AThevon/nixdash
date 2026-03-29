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

  # No args — interactive loop selection
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

  # Build installed set for marking
  local installed_set
  installed_set="$(_search_build_installed_set)"

  local nixdash_bin="$NIXDASH_BIN"

  # Pre-generate the package list with markers (once, reused across iterations)
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

  # Selection loop
  local selected=()

  while true; do
    # Build header with selected packages
    local header="ENTER add · ESC done"
    if [[ ${#selected[@]} -gt 0 ]]; then
      header="Selected (${#selected[@]}): ${selected[*]} │ ENTER add · ESC launch · CTRL-D remove last"
    fi

    # Build preview showing selected + package info
    local preview_cmd="bash '$nixdash_bin' _shell-preview {3} '${selected[*]}'"

    local tmpfile
    tmpfile="$(mktemp)"

    fzf \
      --ansi \
      --height=70% \
      --layout=reverse \
      --border \
      --delimiter " " \
      --header "$header" \
      --preview "$preview_cmd" \
      --preview-window "right:50%:wrap" \
      --bind "ctrl-d:abort" \
      --expect "ctrl-d" \
      < "$pkg_list_file" > "$tmpfile" 2>/dev/null

    local exit_code=$?

    # Read result (first line = key if --expect, second line = selection)
    local key="" pick=""
    if [[ -s "$tmpfile" ]]; then
      key="$(head -1 "$tmpfile")"
      pick="$(tail -n +2 "$tmpfile" | head -1)"
    fi
    rm -f "$tmpfile"

    # ESC or empty = done selecting
    if [[ $exit_code -ne 0 && -z "$key" ]]; then
      break
    fi

    # CTRL-D = remove last selected
    if [[ "$key" == "ctrl-d" ]]; then
      if [[ ${#selected[@]} -gt 0 ]]; then
        local removed="${selected[-1]}"
        unset 'selected[-1]'
        ui_dim "  Removed: $removed" >&2
      fi
      continue
    fi

    # Extract package name from selection
    if [[ -n "$pick" ]]; then
      local pkg_name
      pkg_name="${pick#✓ }"
      pkg_name="${pick#○ }"
      pkg_name="${pkg_name#nixpkgs/ }"
      pkg_name="${pkg_name%% *}"

      if [[ -n "$pkg_name" ]]; then
        # Check if already selected
        local already=0
        for s in "${selected[@]}"; do
          [[ "$s" == "$pkg_name" ]] && { already=1; break; }
        done

        if [[ $already -eq 0 ]]; then
          selected+=("$pkg_name")
          ui_success "  Added: $pkg_name" >&2
        else
          ui_warn "  Already selected: $pkg_name" >&2
        fi
      fi
    fi
  done

  rm -f "$pkg_list_file"

  # Nothing selected
  if [[ ${#selected[@]} -eq 0 ]]; then
    ui_warn "No packages selected"
    return 0
  fi

  # Build nix shell args
  local nix_args=()
  for pkg in "${selected[@]}"; do
    nix_args+=("nixpkgs#$pkg")
  done

  # Show recap
  echo >&2
  ui_info "Launching temporary shell with:"
  for pkg in "${selected[@]}"; do
    echo -e "  ${COLOR_CYAN}•${COLOR_RESET} $pkg" >&2
  done
  echo >&2
  ui_dim "Type 'exit' to leave the temporary shell." >&2
  nix shell "${nix_args[@]}"
}
