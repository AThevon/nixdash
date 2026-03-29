#!/usr/bin/env bash
# nixdash — flake management

# --- Flake parsing/editing functions ---

_flake_file() {
  config_get "flake_file"
}

# flake_list_inputs — list all input names from flake.nix (lines with .url)
flake_list_inputs() {
  local flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  sed -n 's/^[[:space:]]*\([a-zA-Z0-9_-]*\)\.url[[:space:]]*=.*/\1/p' "$flake_file"
}

# flake_get_input_url NAME — extract the URL for a given input
flake_get_input_url() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  local url
  url=$(sed -n "s/^[[:space:]]*${name}\.url[[:space:]]*=[[:space:]]*\"\(.*\)\";/\1/p" "$flake_file")
  echo "$url"
}

# flake_find_inputs_end — find line number of closing }; of inputs block
flake_find_inputs_end() {
  local flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  awk '
    /inputs[[:space:]]*=/ { in_inputs = 1 }
    in_inputs && /^[[:space:]]*\};/ { print NR; exit }
  ' "$flake_file"
}

# flake_find_extra_special_args — find line number of extraSpecialArgs
flake_find_extra_special_args() {
  local flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  grep -n "extraSpecialArgs" "$flake_file" | head -1 | cut -d: -f1
}

# flake_add_input NAME URL — insert input lines before inputs block closing
flake_add_input() {
  local name="$1" url="$2" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  local end_line
  end_line="$(flake_find_inputs_end)"
  [[ -n "$end_line" ]] || return 1
  local insert_text="    ${name}.url = \"${url}\";\n    ${name}.inputs.nixpkgs.follows = \"nixpkgs\";"
  sed -i "${end_line}i\\${insert_text}" "$flake_file"
}

# flake_add_inherit NAME — add name to existing inherit line or create new one in extraSpecialArgs
flake_add_inherit() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  # Try to find an existing inherit line in extraSpecialArgs block
  if grep -q "inherit " "$flake_file"; then
    # Add the name to the existing inherit line
    sed -i "s/\(inherit[[:space:]]\+.*\);/\1 ${name};/" "$flake_file"
  else
    # Find extraSpecialArgs opening and add inherit after it
    local args_line
    args_line="$(flake_find_extra_special_args)"
    [[ -n "$args_line" ]] || return 1
    sed -i "$((args_line + 1))i\\          inherit ${name};" "$flake_file"
  fi
}

# _flake_add_output_arg NAME — add name to outputs function args
_flake_add_output_arg() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1
  # outputs = { self, nixpkgs, ..., ... }:
  # Insert before ", ... }:" or before "... }:"
  sed -i "s/\(outputs[[:space:]]*=[[:space:]]*{[^}]*\),\([[:space:]]*\.\.\.[[:space:]]*}/\1, ${name},\2/" "$flake_file"
}

# flake_remove_input NAME — remove URL, follows, inherit reference, and output arg
flake_remove_input() {
  local name="$1" flake_file
  flake_file="$(_flake_file)"
  [[ -f "$flake_file" ]] || return 1

  # Remove input.url and input.inputs.nixpkgs.follows lines
  sed -i "/^[[:space:]]*${name}\.url[[:space:]]*=/d" "$flake_file"
  sed -i "/^[[:space:]]*${name}\.inputs\./d" "$flake_file"

  # Remove from inherit line — handle both "inherit name;" and "inherit name other;"
  # Case 1: sole inherit → remove the whole line
  sed -i "/^[[:space:]]*inherit[[:space:]]\+${name}[[:space:]]*;/d" "$flake_file"
  # Case 2: first in list → "inherit name other..." → "inherit other..."
  sed -i "s/\(inherit[[:space:]]\+\)${name}[[:space:]]\+/\1/" "$flake_file"
  # Case 3: in the middle or end → "inherit other name..." → "inherit other..."
  sed -i "s/\(inherit[[:space:]]\+.*\)[[:space:]]\+${name}\([[:space:]]*;\)/\1\2/" "$flake_file"

  # Remove from outputs args
  sed -i "s/,\s*${name}\([[:space:]]*,\)/\1/g" "$flake_file"
  sed -i "s/,\s*${name}\([[:space:]]*,\s*\.\.\.\)/\1/g" "$flake_file"
}

# --- Command stubs ---

cmd_add_flake() {
  config_ensure

  # 1. Prompt URL
  local url
  url="$(ui_input "Flake URL (e.g. github:user/repo)")" || return 0
  [[ -z "$url" ]] && { ui_error "URL required"; return 1; }

  # 2. Validate with nix flake metadata
  if ! ui_spin "Validating flake..." nix flake metadata "$url" --no-write-lock-file; then
    ui_error "Invalid or unreachable flake: $url"
    return 1
  fi
  ui_success "Flake is valid"

  # 3. Prompt input name (auto-suggest from URL)
  local suggested_name
  suggested_name="${url##*/}"
  suggested_name="${suggested_name%%#*}"
  local input_name
  input_name="$(ui_input "Input name" "$suggested_name")" || return 0
  [[ -z "$input_name" ]] && { ui_error "Input name required"; return 1; }

  # 4. Prompt package attribute
  local default_attr="packages.\${system}.default"
  local pkg_attr
  pkg_attr="$(ui_input "Package attribute" "$default_attr")" || return 0
  [[ -z "$pkg_attr" ]] && pkg_attr="$default_attr"

  # Full package reference for packages.nix
  local full_pkg="${input_name}.${pkg_attr}"

  # 5. Preview changes
  echo -e "\n${COLOR_BOLD}Summary of changes:${COLOR_RESET}" >&2
  echo -e "  ${COLOR_CYAN}Input:${COLOR_RESET} ${input_name}.url = \"${url}\"" >&2
  echo -e "  ${COLOR_CYAN}Output arg:${COLOR_RESET} ${input_name} added to outputs" >&2
  echo -e "  ${COLOR_CYAN}Inherit:${COLOR_RESET} ${input_name} added to extraSpecialArgs" >&2
  echo -e "  ${COLOR_CYAN}Package:${COLOR_RESET} ${full_pkg} added to packages" >&2
  echo >&2

  # 6. Choose action
  local action
  action="$(ui_choose "$input_name:" \
    "⊕  Install to config" \
    "»  Test in a shell first" \
    "↩  Cancel")" || return 0

  case "$action" in
    *"Test"*)
      ui_info "Launching temporary shell with $url..."
      ui_dim "Type 'exit' to leave the temporary shell."
      nix shell "$url"
      return 0
      ;;
    *"Cancel")
      ui_warn "Cancelled"
      return 0
      ;;
  esac

  # Continue with install...

  # 7. Check structure
  local flake_file
  flake_file="$(_flake_file)"
  local inputs_end
  inputs_end="$(flake_find_inputs_end)"
  local esa_line
  esa_line="$(flake_find_extra_special_args)"

  if [[ -z "$inputs_end" || -z "$esa_line" ]]; then
    ui_warn "flake.nix structure not automatically recognized."
    echo -e "\n${COLOR_BOLD}Manual instructions:${COLOR_RESET}" >&2
    echo -e "  1. Add to inputs:" >&2
    echo -e "     ${COLOR_GREEN}${input_name}.url = \"${url}\";${COLOR_RESET}" >&2
    echo -e "     ${COLOR_GREEN}${input_name}.inputs.nixpkgs.follows = \"nixpkgs\";${COLOR_RESET}" >&2
    echo -e "  2. Add ${COLOR_GREEN}${input_name}${COLOR_RESET} to outputs arguments" >&2
    echo -e "  3. Add ${COLOR_GREEN}inherit ${input_name};${COLOR_RESET} to extraSpecialArgs" >&2
    echo -e "  4. Add ${COLOR_GREEN}${full_pkg}${COLOR_RESET} to your packages file" >&2
    return 0
  fi

  # 8. Apply changes
  local flake_backup pkg_backup
  flake_backup="$(mktemp)"
  cp "$flake_file" "$flake_backup"

  local pkg_file
  pkg_file="$(config_get "packages_file")"
  pkg_backup="$(mktemp)"
  cp "$pkg_file" "$pkg_backup"

  flake_add_input "$input_name" "$url"
  _flake_add_output_arg "$input_name"
  flake_add_inherit "$input_name"
  packages_add "$full_pkg"

  # 9. Show diffs
  ui_info "Changes in flake.nix:"
  ui_diff "$flake_backup" "$flake_file"
  ui_info "Changes in $(basename "$pkg_file"):"
  ui_diff "$pkg_backup" "$pkg_file"

  rm -f "$flake_backup" "$pkg_backup"

  # 10. Apply
  local skip_confirmation
  skip_confirmation="$(config_get "skip_confirmation")"

  if [[ "$skip_confirmation" == "true" ]]; then
    ui_info "Auto-applying..."
  else
    if ! ui_confirm "Apply changes?"; then
      ui_warn "Changes written but not applied"
      return 0
    fi
  fi

  local apply_cmd
  apply_cmd="$(config_get "apply_command")"
  ui_info "Running: $apply_cmd"
  eval "$apply_cmd"
  ui_success "Flake ${input_name} added and applied"
}

cmd_init() {
  # 1. Welcome
  echo -e "\n${COLOR_BOLD}Welcome to nixdash!${COLOR_RESET}" >&2
  echo -e "${COLOR_DIM}Initial setup wizard${COLOR_RESET}\n" >&2

  # 2. Detect flake.nix
  local flake_file=""
  local search_dirs=("$HOME/.dotfiles" "$HOME/nixos-config" "$HOME/.config/nixos" ".")
  for dir in "${search_dirs[@]}"; do
    if [[ -f "$dir/flake.nix" ]]; then
      flake_file="$(cd "$dir" && pwd)/flake.nix"
      break
    fi
  done

  # 3. Prompt flake file path
  if [[ -n "$flake_file" ]]; then
    ui_info "Flake file detected: $flake_file"
  else
    ui_warn "No flake.nix detected automatically"
  fi
  flake_file="$(ui_input "Path to flake.nix" "$flake_file")" || return 0
  [[ -z "$flake_file" ]] && { ui_error "Flake path required"; return 1; }

  if [[ ! -f "$flake_file" ]]; then
    ui_error "File not found: $flake_file"
    return 1
  fi

  # 4. Detect packages file
  local flake_dir
  flake_dir="$(dirname "$flake_file")"
  local pkg_file=""

  # Try home.packages first
  local match
  match="$(grep -rl "home\.packages" "$flake_dir" --include="*.nix" 2>/dev/null | head -1)" || true
  if [[ -n "$match" ]]; then
    pkg_file="$match"
  else
    # 5. Try environment.systemPackages (NixOS)
    match="$(grep -rl "environment\.systemPackages" "$flake_dir" --include="*.nix" 2>/dev/null | head -1)" || true
    if [[ -n "$match" ]]; then
      pkg_file="$match"
    fi
  fi

  # 6. Prompt packages file path
  if [[ -n "$pkg_file" ]]; then
    ui_info "Packages file detected: $pkg_file"
  else
    ui_warn "No packages file detected"
  fi
  pkg_file="$(ui_input "Path to packages file" "$pkg_file")" || return 0
  [[ -z "$pkg_file" ]] && { ui_error "Packages file path required"; return 1; }

  if [[ ! -f "$pkg_file" ]]; then
    ui_error "File not found: $pkg_file"
    return 1
  fi

  # 7. Count packages
  local tmp_config_dir tmp_config_file
  tmp_config_dir="$(mktemp -d)"
  tmp_config_file="$tmp_config_dir/config.toml"
  # Temporarily set config to count packages
  local orig_config_dir="$CONFIG_DIR" orig_config_file="$CONFIG_FILE"
  CONFIG_DIR="$tmp_config_dir"
  CONFIG_FILE="$tmp_config_file"
  config_set "packages_file" "$pkg_file"
  config_set "flake_file" "$flake_file"
  config_set "apply_command" "echo placeholder"
  _packages_parse
  local pkg_count=0
  if [[ -n "$_PACKAGES_CACHE" ]]; then
    pkg_count="$(echo "$_PACKAGES_CACHE" | wc -l)"
  fi
  CONFIG_DIR="$orig_config_dir"
  CONFIG_FILE="$orig_config_file"
  rm -rf "$tmp_config_dir"
  ui_info "$pkg_count packages detected"

  # 8. Detect apply command
  local apply_cmd=""
  if grep -q "home-manager\|homeManagerConfiguration\|homeConfigurations" "$flake_file" 2>/dev/null; then
    apply_cmd="home-manager switch --flake $(dirname "$flake_file")"
  elif grep -q "nixosConfigurations\|nixos-rebuild" "$flake_file" 2>/dev/null; then
    apply_cmd="sudo nixos-rebuild switch --flake $(dirname "$flake_file")"
  fi

  # 9. Prompt apply command
  if [[ -n "$apply_cmd" ]]; then
    ui_info "Apply command detected: $apply_cmd"
  else
    ui_warn "Apply command not detected"
  fi
  apply_cmd="$(ui_input "Apply command" "$apply_cmd")" || return 0
  [[ -z "$apply_cmd" ]] && { ui_error "Apply command required"; return 1; }

  # 10. Auto apply = false
  local skip_confirmation="false"

  # 11. Analyze flake structure
  local structure_info=""
  # Temporarily configure to analyze
  local save_dir="$CONFIG_DIR" save_file="$CONFIG_FILE"
  local analysis_dir
  analysis_dir="$(mktemp -d)"
  CONFIG_DIR="$analysis_dir"
  CONFIG_FILE="$analysis_dir/config.toml"
  config_set "flake_file" "$flake_file"
  local inputs_end esa_line
  inputs_end="$(flake_find_inputs_end)" || true
  esa_line="$(flake_find_extra_special_args)" || true
  CONFIG_DIR="$save_dir"
  CONFIG_FILE="$save_file"
  rm -rf "$analysis_dir"

  if [[ -n "$inputs_end" && -n "$esa_line" ]]; then
    structure_info="complete"
    ui_success "Flake structure recognized (inputs end: L${inputs_end}, extraSpecialArgs: L${esa_line})"
  else
    structure_info="partial"
    ui_warn "Flake structure partially recognized — add-flake will show manual instructions"
  fi

  # 12. Check nix-search-tv
  if command -v nix-search-tv &>/dev/null; then
    ui_success "nix-search-tv available"
  else
    ui_warn "nix-search-tv not found — search will not work"
    ui_dim "Install it: nix profile install github:peterldowns/nix-search-tv"
  fi

  # 13. Save config
  config_set "flake_file" "$flake_file"
  config_set "packages_file" "$pkg_file"
  config_set "apply_command" "$apply_cmd"
  config_set "skip_confirmation" "$skip_confirmation"

  echo >&2
  ui_success "Configuration saved to $CONFIG_FILE"
  echo -e "  ${COLOR_DIM}flake_file    = $flake_file${COLOR_RESET}" >&2
  echo -e "  ${COLOR_DIM}packages_file = $pkg_file${COLOR_RESET}" >&2
  echo -e "  ${COLOR_DIM}apply_command = $apply_cmd${COLOR_RESET}" >&2
  echo -e "  ${COLOR_DIM}skip_confirmation    = $skip_confirmation${COLOR_RESET}" >&2
  echo -e "\n${COLOR_GREEN}nixdash is ready!${COLOR_RESET} Run ${COLOR_BOLD}nixdash${COLOR_RESET} to get started.\n" >&2
}

_config_preview() {
  local key="$1"
  case "$key" in
    packages_file)
      echo -e "${COLOR_VIOLET}▪${COLOR_RESET}  Packages file"
      echo ""
      echo "Path to the .nix file containing"
      echo "the home.packages list."
      echo ""
      echo "nixdash reads and modifies this file to"
      echo "add/remove packages."
      ;;
    apply_command)
      echo -e "${COLOR_VIOLET}▸${COLOR_RESET}  Apply command"
      echo ""
      echo "Command run after each package change"
      echo "(add or remove)."
      echo ""
      echo "Examples:"
      echo "  home-manager switch --flake ~/.dotfiles"
      echo "  sudo nixos-rebuild switch --flake ."
      ;;
    flake_file)
      echo -e "${COLOR_VIOLET}◈${COLOR_RESET}  Flake file"
      echo ""
      echo "Path to flake.nix."
      echo ""
      echo "Used to add flake inputs and"
      echo "detect external packages."
      ;;
    skip_confirmation)
      echo -e "${COLOR_GREEN}◉${COLOR_RESET}  Skip confirmation"
      echo ""
      echo "When enabled, nixdash applies changes"
      echo "immediately without asking for confirmation."
      echo ""
      echo "When disabled, a diff is shown and"
      echo "confirmation is required before applying."
      ;;
    update_index)
      echo -e "${COLOR_VIOLET}↻${COLOR_RESET}  Update index"
      echo ""
      echo "Downloads the latest nix-search-tv index"
      echo "for package search."
      echo ""
      echo "Run regularly to get the latest"
      echo "nixpkgs versions."
      ;;
    redetect)
      echo -e "${COLOR_VIOLET}⟳${COLOR_RESET}  Re-run detection"
      echo ""
      echo "Restarts the initial setup wizard"
      echo "(nixdash init)."
      echo ""
      echo "Useful if you moved your files or"
      echo "changed your Nix configuration."
      ;;
    back)
      echo "Back to hub"
      ;;
  esac
}

cmd_config() {
  config_ensure

  local nixdash_bin="$NIXDASH_BIN"

  while true; do
    local pkg_file flake_file apply_cmd skip_confirmation
    pkg_file="$(config_get "packages_file")"
    flake_file="$(config_get "flake_file")"
    apply_cmd="$(config_get "apply_command")"
    skip_confirmation="$(config_get "skip_confirmation")"

    local auto_label="no"
    [[ "$skip_confirmation" == "true" ]] && auto_label="yes"

    local tmpfile
    tmpfile="$(mktemp)"

    printf '%s\n' \
      "packages_file │ ${COLOR_VIOLET}▪${COLOR_RESET}  Packages file: $pkg_file" \
      "apply_command │ ${COLOR_VIOLET}▸${COLOR_RESET}  Apply command: $apply_cmd" \
      "flake_file    │ ${COLOR_VIOLET}◈${COLOR_RESET}  Flake file: $flake_file" \
      "skip_confirmation    │ ${COLOR_GREEN}◉${COLOR_RESET}  Skip confirmation: $auto_label" \
      "update_index  │ ${COLOR_VIOLET}↻${COLOR_RESET}  Update nix-search-tv index" \
      "redetect      │ ${COLOR_VIOLET}⟳${COLOR_RESET}  Re-run detection (nixdash init)" \
      "back          │ ${COLOR_DIM}↩${COLOR_RESET}  Back" \
    | fzf \
      --ansi \
      --no-sort \
      --height=50% \
      --layout=reverse \
      --border \
      --header "nixdash settings" \
      --preview "bash '$nixdash_bin' _config-preview {1}" \
      --preview-window "right:50%:wrap" \
      --delimiter "│" \
      --with-nth 2.. \
    > "$tmpfile" || { rm -f "$tmpfile"; return 0; }

    local choice
    choice="$(cat "$tmpfile")"
    rm -f "$tmpfile"

    local cmd
    cmd="$(echo "$choice" | awk -F'│' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')"

    case "$cmd" in
      packages_file)
        local new_val
        new_val="$(ui_input "Path to packages file" "$pkg_file")" || continue
        [[ -n "$new_val" ]] && config_set "packages_file" "$new_val"
        ui_success "Packages file updated"
        ;;
      apply_command)
        local new_val
        new_val="$(ui_input "Apply command" "$apply_cmd")" || continue
        [[ -n "$new_val" ]] && config_set "apply_command" "$new_val"
        ui_success "Apply command updated"
        ;;
      flake_file)
        local new_val
        new_val="$(ui_input "Path to flake.nix" "$flake_file")" || continue
        [[ -n "$new_val" ]] && config_set "flake_file" "$new_val"
        ui_success "Flake file updated"
        ;;
      skip_confirmation)
        if [[ "$skip_confirmation" == "true" ]]; then
          config_set "skip_confirmation" "false"
          ui_success "Confirmation re-enabled"
        else
          config_set "skip_confirmation" "true"
          ui_success "Confirmation disabled"
        fi
        ;;
      update_index)
        if command -v nix-search-tv &>/dev/null; then
          ui_spin "Updating nix-search-tv index..." nix-search-tv fetch
          ui_success "Index updated"
        else
          ui_error "nix-search-tv is not installed"
        fi
        ;;
      redetect)
        cmd_init
        return 0
        ;;
      back)
        return 0
        ;;
    esac
  done
}
