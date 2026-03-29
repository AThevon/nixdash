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
  url="$(ui_input "URL du flake (ex: github:user/repo)")" || return 0
  [[ -z "$url" ]] && { ui_error "URL requise"; return 1; }

  # 2. Validate with nix flake metadata
  if ! ui_spin "Validation du flake..." nix flake metadata "$url" --no-write-lock-file; then
    ui_error "Flake invalide ou inaccessible : $url"
    return 1
  fi
  ui_success "Flake valide"

  # 3. Prompt input name (auto-suggest from URL)
  local suggested_name
  suggested_name="${url##*/}"
  suggested_name="${suggested_name%%#*}"
  local input_name
  input_name="$(ui_input "Nom de l'input" "$suggested_name")" || return 0
  [[ -z "$input_name" ]] && { ui_error "Nom d'input requis"; return 1; }

  # 4. Prompt package attribute
  local default_attr="packages.\${system}.default"
  local pkg_attr
  pkg_attr="$(ui_input "Attribut du package" "$default_attr")" || return 0
  [[ -z "$pkg_attr" ]] && pkg_attr="$default_attr"

  # Full package reference for packages.nix
  local full_pkg="${input_name}.${pkg_attr}"

  # 5. Preview changes
  echo -e "\n${COLOR_BOLD}Résumé des modifications :${COLOR_RESET}" >&2
  echo -e "  ${COLOR_CYAN}Input :${COLOR_RESET} ${input_name}.url = \"${url}\"" >&2
  echo -e "  ${COLOR_CYAN}Output arg :${COLOR_RESET} ${input_name} ajouté aux outputs" >&2
  echo -e "  ${COLOR_CYAN}Inherit :${COLOR_RESET} ${input_name} ajouté à extraSpecialArgs" >&2
  echo -e "  ${COLOR_CYAN}Package :${COLOR_RESET} ${full_pkg} ajouté aux packages" >&2
  echo >&2

  # 6. Confirm
  if ! ui_confirm "Appliquer ces modifications ?"; then
    ui_warn "Annulé"
    return 0
  fi

  # 7. Check structure
  local flake_file
  flake_file="$(_flake_file)"
  local inputs_end
  inputs_end="$(flake_find_inputs_end)"
  local esa_line
  esa_line="$(flake_find_extra_special_args)"

  if [[ -z "$inputs_end" || -z "$esa_line" ]]; then
    ui_warn "Structure du flake.nix non reconnue automatiquement."
    echo -e "\n${COLOR_BOLD}Instructions manuelles :${COLOR_RESET}" >&2
    echo -e "  1. Ajouter dans inputs :" >&2
    echo -e "     ${COLOR_GREEN}${input_name}.url = \"${url}\";${COLOR_RESET}" >&2
    echo -e "     ${COLOR_GREEN}${input_name}.inputs.nixpkgs.follows = \"nixpkgs\";${COLOR_RESET}" >&2
    echo -e "  2. Ajouter ${COLOR_GREEN}${input_name}${COLOR_RESET} aux arguments de outputs" >&2
    echo -e "  3. Ajouter ${COLOR_GREEN}inherit ${input_name};${COLOR_RESET} dans extraSpecialArgs" >&2
    echo -e "  4. Ajouter ${COLOR_GREEN}${full_pkg}${COLOR_RESET} dans votre fichier packages" >&2
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
  ui_info "Modifications dans flake.nix :"
  ui_diff "$flake_backup" "$flake_file"
  ui_info "Modifications dans $(basename "$pkg_file") :"
  ui_diff "$pkg_backup" "$pkg_file"

  rm -f "$flake_backup" "$pkg_backup"

  # 10. Apply
  local auto_apply
  auto_apply="$(config_get "auto_apply")"

  if [[ "$auto_apply" == "true" ]]; then
    ui_info "Application automatique..."
  else
    if ! ui_confirm "Appliquer les changements ?"; then
      ui_warn "Modifications écrites mais non appliquées"
      return 0
    fi
  fi

  local apply_cmd
  apply_cmd="$(config_get "apply_command")"
  ui_info "Exécution : $apply_cmd"
  eval "$apply_cmd"
  ui_success "Flake ${input_name} ajouté et appliqué"
}

cmd_init() {
  echo "[stub] nixdash init — not yet implemented" >&2
}

cmd_config() {
  echo "[stub] nixdash config — not yet implemented" >&2
}
