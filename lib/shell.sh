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

  local selection
  selection="$(search_fzf --multiselect)" || return 0
  [[ -z "$selection" ]] && return 0

  # Build nix shell args
  local nix_args=()
  local pkg
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    nix_args+=("nixpkgs#$pkg")
  done <<< "$selection"

  if [[ ${#nix_args[@]} -eq 0 ]]; then
    ui_warn "No packages selected"
    return 0
  fi

  # Show recap
  ui_info "Selected packages:"
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    echo -e "  ${COLOR_CYAN}•${COLOR_RESET} $pkg" >&2
  done <<< "$selection"
  echo >&2

  ui_info "Launching: nix shell ${nix_args[*]}"
  exec nix shell "${nix_args[@]}"
}
